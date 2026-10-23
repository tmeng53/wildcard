#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import CheckInDomain
import Contracts
import DesignSystem
import DesignSystemUI
import Foundation
import Observation
import OnboardingDomain

/// Who is on the stage and what has happened so far, from the clock.
@MainActor @Observable
final class EntranceStage {
    /// A teammate where home will put them.
    struct Placed {
        let index: Int
        let member: CastMember
        let position: StagePosition
    }

    /// The character's canvas and where its feet stand in it, as home draws it.
    static let canvas = CGSize(width: 240, height: 320)
    static let canvasFeet = CGPoint(x: 120, y: 316)
    /// The area the entrance clip crosses, in canvas points: from 911 to the right of the spot
    /// to a little left of it, and up over the top of the jump.
    static let runway = CGRect(x: -60, y: -380, width: 1280, height: 710)
    /// How tall a line's tail stands over the feet, in canvas points: just above the head.
    static let headHeight = 292.0
    /// The head and shoulders, in canvas points, for the squad card's rings.
    static let head = CGRect(x: 50, y: 20, width: 140, height: 140)

    private(set) var newcomer: CastMember?
    /// The teammates, in the order they joined, where home puts them.
    private(set) var placed: [Placed] = []
    private(set) var motion: EntranceMotion?
    /// When the entrance started playing; nil while everyone is still being built.
    private(set) var start: Date?
    /// One welcome line per speaker, String Catalog keys: the new member's first.
    private(set) var lines: [String] = []
    private(set) var isRunning = false
    private(set) var hasLanded = false
    private(set) var landedAt: Date?
    /// The lines up now, by index into `lines`.
    private(set) var speaking: Set<Int> = []
    private(set) var showsCard = false
    private(set) var myHeadIn = false
    private(set) var countFlipped = false
    private(set) var showsChrome = false

    /// The teammates in the order they are drawn: furthest back first.
    var backToFront: [Placed] {
        placed.sorted { $0.position.point.y < $1.position.point.y }
    }

    /// Seconds since the entrance started. With Reduce Motion, how it stands once landed.
    func time(at date: Date, reduceMotion: Bool) -> Double {
        if reduceMotion { return EntranceScript.land + 1 }
        guard let start else { return 0 }
        return date.timeIntervalSince(start)
    }

    /// Where the new member's feet are across the runway's drawn area, from 0 to 1, to turn
    /// them about.
    func runwayAnchor(at time: Double) -> Double {
        let runway = Self.runway
        let across =
            ((motion?.newcomerX(at: time) ?? StageLayout.mySpot.x) - StageLayout.mySpot.x) / StageLayout.myScale
        return (Self.canvasFeet.x + across - runway.minX) / runway.width
    }

    /// The new member's head over their feet, in screen points, for the bubble's tail.
    static func myHeight(unit: Double) -> Double {
        headHeight * StageLayout.myScale * unit
    }

    /// The script in screen points for a screen `unit` points per stage point wide. When things
    /// happen doesn't depend on the screen's size.
    func script(unit: Double) -> EntranceScript {
        EntranceScript(
            spot: Point(x: StageLayout.mySpot.x * unit, y: StageLayout.mySpot.y * unit),
            teammates: placed.map {
                EntranceScript.Teammate(
                    feet: Point(x: $0.position.point.x * unit, y: $0.position.point.y * unit),
                    height: Self.headHeight * $0.position.scale * unit)
            })
    }

    /// Builds everyone, places the squad as home will, then plays the moment through to its end.
    /// With Reduce Motion it shows how it ends, with every line up, for the time it takes to
    /// read them.
    func play(newcomer member: CastMember, teammates squad: [CastMember], on scene: SceneTheme, reduceMotion: Bool)
        async
    {
        let newcomer = CastMember(outfit: member.look, persona: member.persona)
        self.newcomer = newcomer
        await set(squad, on: scene, reduceMotion: reduceMotion)
        await newcomer.load(idle: !reduceMotion)
        let entrance = try? PlaceholderCharacter.entrance()
        if let entrance {
            motion = EntranceMotion(
                spot: Point(x: StageLayout.mySpot.x, y: StageLayout.mySpot.y), scale: StageLayout.myScale,
                entrance: entrance)
        }
        let script = script(unit: 1)
        if reduceMotion {
            isRunning = true
            hasLanded = true
            speaking = Set(lines.indices)
            showsCard = true
            myHeadIn = true
            countFlipped = true
            showsChrome = true
            await wait(until: EntranceScript.lineDuration, from: .now)
            return
        }
        let start = Date.now
        self.start = start
        let events = events(newcomer: newcomer, entrance: entrance, script: script, start: start)
        for event in events.sorted(by: { $0.time < $1.time }) {
            await wait(until: event.time, from: start)
            guard !Task.isCancelled else { return }
            event.run()
        }
        await wait(until: script.end, from: start)
    }

    /// Places the squad as home will, picks everyone's line and builds the teammates.
    private func set(_ squad: [CastMember], on scene: SceneTheme, reduceMotion: Bool) async {
        var squadStage = SquadStage(layout: StageLayout.of(scene))
        let ids = squad.map { _ in MemberID(UUID()) }
        squadStage.arrange(
            zip(ids, squad).map {
                StageMember(id: $0, status: .notYet, firstCheckInAt: nil, keepsToTheBack: $1.persona == .shy)
            })
        placed = zip(ids, squad).enumerated().compactMap { index, pair in
            squadStage.position(of: pair.0, at: 0).map { Placed(index: index, member: pair.1, position: $0) }
        }
        let shown = placed.map(\.member)
        var generator = SystemRandomNumberGenerator()
        lines = WelcomeLines.pick(for: [.newcomer] + shown.map { .teammate($0.persona) }, using: &generator)
        for teammate in shown { await teammate.load(idle: !reduceMotion) }
    }

    /// What happens when, in seconds from `start`.
    private func events(newcomer: CastMember, entrance: Clip?, script: EntranceScript, start: Date)
        -> [(time: Double, run: () -> Void)]
    {
        var events: [(time: Double, run: () -> Void)] = [
            (EntranceScript.run, { [weak self] in self?.run(newcomer, entrance: entrance, at: start) }),
            (EntranceScript.look, { [weak self] in self?.watch(cheers: script.cheers, from: start) }),
            (EntranceScript.land, { [weak self] in self?.land() }),
            (
                script.myLine,
                { [weak self] in
                    self?.say(0)
                    newcomer.play("cheer")
                }
            ),
            (script.myLine + EntranceScript.lineDuration, { [weak self] in self?.hush(0) }),
            (EntranceScript.cardDrop, { [weak self] in self?.showsCard = true }),
            (EntranceScript.chromeRise, { [weak self] in self?.showsChrome = true }),
            (EntranceScript.countFlip, { [weak self] in self?.countFlipped = true }),
            (EntranceScript.myHeadPop, { [weak self] in self?.myHeadIn = true }),
        ]
        for (index, (mate, time)) in zip(placed, script.cheers).enumerated() {
            events.append(
                (
                    time,
                    { [weak self] in
                        self?.say(index + 1)
                        mate.member.play("welcome")
                    }
                ))
            events.append((time + EntranceScript.lineDuration, { [weak self] in self?.hush(index + 1) }))
        }
        return events
    }

    /// The squad card's row as home shows it: the teammates, then the new member once their
    /// head has popped in, none checked in yet.
    var cardMembers: [SquadMember] {
        let mates = placed.map { SquadMember(id: "\($0.index)", status: .open, isMe: false) }
        return myHeadIn ? mates + [SquadMember(id: Self.mine, status: .open, isMe: true)] : mates
    }

    func player(for member: SquadMember) -> CharacterPlayer? {
        if member.id == Self.mine { return newcomer?.player }
        return placed.first { "\($0.index)" == member.id }?.member.player
    }

    private static let mine = "me"

    private func run(_ newcomer: CastMember, entrance: Clip?, at start: Date) {
        guard let entrance else { return }
        newcomer.play(entrance, now: start.addingTimeInterval(EntranceScript.run), blending: false)
        isRunning = true
    }

    /// Everyone turns to follow the runner until their own cheer.
    private func watch(cheers: [Double], from start: Date) {
        guard let motion else { return }
        for (mate, cheer) in zip(placed, cheers) {
            let feet = Point(x: mate.position.point.x, y: mate.position.point.y)
            guard
                let clip = try? motion.watching(
                    from: feet, facing: mate.position.facing, until: cheer, bounces: mate.member.persona == .energetic)
            else { continue }
            mate.member.play(clip, now: start.addingTimeInterval(EntranceScript.look))
        }
    }

    private func land() {
        hasLanded = true
        landedAt = .now
    }

    private func say(_ index: Int) { speaking.insert(index) }
    private func hush(_ index: Int) { speaking.remove(index) }

    private func wait(until seconds: Double, from start: Date) async {
        let left = seconds - Date.now.timeIntervalSince(start)
        if left > 0 { try? await Task.sleep(for: .seconds(left)) }
    }
}

#endif
