import Backend
import CheckInDomain
import CheckInUI
import Contracts
import DesignSystem
import Foundation

/// Each squad's scene as the app last read it, kept on this phone so 今天 opens on it when the
/// server is slow or out of reach, rather than on the gym and then switching.
enum KeptScene {
    private struct Saved: Codable {
        var version = 1
        let scene: String
    }

    private static let prefix = "scene."

    private static func key(_ squad: SquadID) -> String { prefix + squad.description }

    static func save(_ scene: SceneTheme, of squad: SquadID) {
        guard let data = try? JSONEncoder().encode(Saved(scene: scene.rawValue)) else { return }
        UserDefaults.standard.set(data, forKey: key(squad))
    }

    static func scene(of squad: SquadID) -> SceneTheme? {
        guard let data = UserDefaults.standard.data(forKey: key(squad)),
            let saved = try? JSONDecoder().decode(Saved.self, from: data), saved.version == 1
        else { return nil }
        return SceneTheme(rawValue: saved.scene)
    }

    /// Signing out forgets every squad's scene with the rest of what the phone kept.
    static func forgetAll() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }
}

/// The squad's scene as read from the server, and the move that brought it there since this
/// phone last showed the squad, if a teammate made one.
struct ReadScene: Sendable {
    let scene: SceneTheme
    let move: SceneMove?

    /// Compares what the server says with the scene this phone kept, and keeps the new one, so a
    /// teammate's move is told once. On the main actor, with no wait between reading and saving,
    /// so two reads that arrive together can't both tell it; called only when the result will be
    /// used, so a read dropped on the way (a launch that stopped waiting) doesn't lose the move.
    /// Without a member (home not loaded yet) it keeps nothing, and the next read tells the move.
    @MainActor static func keep(_ read: SquadScene, of squad: SquadID, member: MemberID?) -> ReadScene {
        let scene = SceneTheme(rawValue: read.scene.rawValue) ?? .gym
        guard let member else { return ReadScene(scene: scene, move: nil) }
        let move = SceneMove(from: KeptScene.scene(of: squad), to: read, member: member)
        // A takeover (a holiday's) is nobody's pick: the phone keeps the squad's own scene, so the
        // day after doesn't read as a teammate moving the squad back.
        if read.takeover == nil { KeptScene.save(scene, of: squad) }
        return ReadScene(scene: scene, move: move)
    }
}

/// Reading the squad's scene, which 今天 must open on rather than switch to.
extension AppModel {
    /// Whoever made the squad drops onto the scene they picked. On a day a holiday's scene takes
    /// over every home, its opening plays first, as it does for a joiner after 上场, and its 进场
    /// drops the squad onto the holiday's scene; the pick stays the squad's own underneath.
    func landNewSquad(on picked: SceneTheme, home: Home, today: TodayModel) async {
        guard let read = await openingScene(of: home.squad.id), let takeover = read.takeover else {
            await today.dropIn(on: picked, coveredAt: .now)
            return
        }
        let shown = SceneTheme(rawValue: read.scene.rawValue) ?? picked
        await today.land(on: shown, move: nil, takeover: takeover)
        // Its opening already played on this phone today: just the drop.
        if !today.isShowingOpening { await today.dropIn(on: shown, coveredAt: .now) }
    }

    /// Puts 今天 on the squad's scene this week, dropping the squad onto it when a teammate moved
    /// it. Offline, it stays where it is.
    func readScene(of squad: SquadID?, into today: TodayModel) async {
        guard let squad, let read = try? await api.scene(of: squad) else { return }
        let kept = ReadScene.keep(read, of: squad, member: today.home?.member)
        await today.land(on: kept.scene, move: kept.move, takeover: read.takeover)
    }

    /// The squad's scene this week from the server, unless it takes longer than `Self.sceneWait`.
    func openingScene(of squad: SquadID) async -> SquadScene? {
        let wait = Self.sceneWait
        return await withTaskGroup(of: SquadScene?.self) { group in
            group.addTask { try? await self.api.scene(of: squad) }
            group.addTask {
                try? await Task.sleep(for: wait)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}

extension LaunchOptions {
    /// `-uitest-takeover trot`: a takeover scene stands in for the sample squad's once 今天 is up,
    /// so UI tests see its opening (the bundled art at `openings/trot/`), 进场 and the drop.
    static var takeover: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-uitest-takeover"), flag + 1 < arguments.count else { return nil }
        return arguments[flag + 1]
    }
}

/// The squad's scene, which 今天 must open on rather than switch to.
extension AppModel {
    /// Runs `work` under the launch cover: signing in on the open screen waits here too, for a
    /// member whose squad is already set up, rather than sitting on a button that seems to do
    /// nothing.
    func withLaunchCover<Value>(_ work: () async -> Value) async -> Value {
        guard case .signUp = screen else { return await work() }
        screen = .starting
        openingUnderCover = true
        defer { openingUnderCover = false }
        return await work()
    }

    /// How long the loading screen waits for the squad's scene before opening on the kept one.
    static let sceneWait = Duration.seconds(3)
}
