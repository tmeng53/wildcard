import CheckInDomain
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
        KeptScene.save(scene, of: squad)
        return ReadScene(scene: scene, move: move)
    }
}
