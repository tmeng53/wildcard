#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import CheckInDomain
import Contracts
import DesignSystemUI
import Foundation
import Observation

/// 拍一拍 on the home scene (the approved C, 隔空拍). Tapping a teammate hops them (their card,
/// with what they're up to and 「拍一拍」, pops up over the app); patting jabs from where I stand, a graphite (brand) dot
/// flies over, a 「!」 pops over them and they take it their persona's way. On opening the home,
/// whoever patted me does the same to me from where they stand, once, and their bubble offers
/// one back.
@MainActor @Observable
final class PatStage {
    /// Someone on the scene.
    enum Figure: Hashable {
        case mine
        case mate(MemberID)
    }

    /// A pat under way, from its first frame.
    struct Pat: Equatable {
        let patter: Figure
        let patted: Figure
        let start: Date
        /// How long it plays: until both the pat and the reaction are over.
        let duration: Double
    }

    /// What a teammate's bubble is for: the squad's news, never a tap (Tracy, 2026-11-04: a tap
    /// opens a card, and bubbles are only for what happens by itself).
    enum BubbleKind: Equatable {
        /// They just patted me.
        case pattedMe
        /// They joined the squad since the home was last shown.
        case joined
    }

    /// A line over my own head: the squad's news for me, such as 「你现在是队长了」.
    struct MyLine: Equatable {
        let text: String
        /// Bumps each time a line opens, as `Bubble.id` does.
        let id: Int
    }

    /// The bubble over a teammate.
    struct Bubble: Equatable {
        let mate: MemberID
        let kind: BubbleKind
        let title: String
        let detail: String?
        /// Bumps each time a bubble opens, so a new one replaces an old one with its pop.
        let id: Int
    }

    private(set) var pat: Pat?
    private(set) var bubble: Bubble?
    private(set) var myLine: MyLine?
    /// When each teammate last hopped at a tap.
    private(set) var hops: [MemberID: Date] = [:]
    /// Bumps when my pat lands on a teammate: the one haptic, `Haptic.poke`.
    private(set) var landed = 0
    /// Bumps when a teammate's pat lands on me: `Haptic.reaction`.
    private(set) var landedOnMe = 0

    private var bubbles = 0

    /// When in a pat the dot leaves my hand, lands, and how long the dot rests after.
    nonisolated static let dotLeaves = 0.45
    nonisolated static let dotLands = PlaceholderCharacter.patContact - 0.1
    /// How long a tapped teammate's bubble stays up.
    nonisolated static let bubbleHold = 5.0
    /// How long this stage's bubbles stay up: `bubbleHold`, or longer for UI tests, whose slow
    /// simulators can spend 5 seconds on finding a bubble.
    let hold: Double

    init(bubbleHold hold: Double = PatStage.bubbleHold) {
        self.hold = hold
    }
    /// How long after opening the home a teammate pats me.
    nonisolated static let patMeDelay = 1.0
    /// A tapped teammate's hop: how long, and how high in the rig's points at the stage's
    /// scale of 0.25 (the approved home).
    nonisolated static let hop = (duration: 0.5, height: 14.0)

    // MARK: Tapping a teammate

    /// A teammate was tapped: they hop and cheer if awake and not mid-sport, and any bubble
    /// closes; their card opens over the app. Returns their pose, nil while a pat plays.
    @discardableResult
    func tap(_ mate: SquadCast.Mate, cast: SquadCast, phase: DayPhase, now: Date = .now) -> StagePose? {
        guard pat == nil else { return nil }
        bubble = nil
        return hop(mate, cast: cast, phase: phase, now: now)
    }

    /// `mate` hops, and cheers if awake and not mid-sport; returns their pose.
    private func hop(_ mate: SquadCast.Mate, cast: SquadCast, phase: DayPhase, now: Date) -> StagePose {
        hops[mate.id] = now
        let pose = cast.stage.pose(of: mate.member, at: phase)
        switch pose {
        case .standing, .sitting, .holdingSign:
            if let clip = try? PlaceholderCharacter.clip("cheer", persona: mate.persona, species: mate.species) {
                try? mate.player.play(clip, now: now)
            }
        case .station, .inPlace, .eating, .asleep:
            break
        }
        return pose
    }

    // MARK: The squad's news

    /// Teammates who joined since the home was last shown: the first hops in and their bubble
    /// says 「新队友 X 上场」, naming the next one, with 「拍一拍」 like any teammate's.
    func welcome(_ joined: [SquadCast.Mate], cast: SquadCast, phase: DayPhase, now: Date = .now) {
        guard pat == nil, let first = joined.first else { return }
        _ = hop(first, cast: cast, phase: phase, now: now)
        let mate = String(copy: "队友", bundle: .module)
        show(
            Bubble(
                mate: first.id, kind: .joined,
                title: String(copy: "新队友 \(first.name ?? mate) 上场", bundle: .module),
                detail: joined.dropFirst().first.map {
                    String(copy: "\($0.name ?? mate) 也上场了", bundle: .module)
                },
                id: nextBubble()), for: hold)
    }

    /// A line over my own head for `hold`.
    func say(_ text: String) {
        let line = MyLine(text: text, id: nextBubble())
        myLine = line
        Task { @MainActor [weak self, hold] in
            try? await Task.sleep(for: .seconds(hold))
            if self?.myLine == line { self?.myLine = nil }
        }
    }

    /// A tap anywhere else on the scene closes the bubble.
    func dismissBubble() {
        bubble = nil
    }

    // MARK: Patting

    /// I pat `mate` from where I stand, unless another pat is playing; says whether it started,
    /// so the caller sends only a pat that was seen.
    @discardableResult
    func pat(_ mate: SquadCast.Mate, mine: CharacterPlayer?, now: Date = .now) -> Bool {
        guard pat == nil, let mine, let jab = try? PlaceholderCharacter.patMove(),
            let reaction = try? PlaceholderCharacter.pattedMove(mate.persona)
        else { return false }
        bubble = nil
        play(patter: (.mine, mine, jab), patted: (.mate(mate.id), mate.player, reaction), now: now) { [weak self] in
            self?.landed += 1
        } finished: {
        }
        return true
    }

    /// `mate` pats me, from where they stand, then their bubble says so and offers one back.
    /// `others` also patted me: the first of them is named on the bubble's second line. Says
    /// whether it started, so pats that couldn't play yet play on the next open.
    @discardableResult
    func patMe(
        by mate: SquadCast.Mate, others: [SquadCast.Mate], mine: CharacterPlayer?, myPersona: Persona,
        now: Date = .now
    ) -> Bool {
        guard pat == nil, let mine, let jab = try? PlaceholderCharacter.patMove(),
            let reaction = try? PlaceholderCharacter.pattedMove(myPersona)
        else { return false }
        bubble = nil
        play(patter: (.mate(mate.id), mate.player, jab), patted: (.mine, mine, reaction), now: now) { [weak self] in
            self?.landedOnMe += 1
        } finished: { [weak self] in
            guard let self else { return }
            let name = mate.name ?? String(copy: "队友", bundle: .module)
            show(
                Bubble(
                    mate: mate.id, kind: .pattedMe,
                    title: String(copy: "\(name)拍了拍你", bundle: .module),
                    detail: others.first.map {
                        String(
                            copy: "\($0.name ?? String(copy: "队友", bundle: .module)) 也拍了拍你",
                            bundle: .module)
                    },
                    id: nextBubble()), for: hold)
        }
        return true
    }

    /// Plays one pat: the jab now, the reaction from the contact, the haptic as the dot lands.
    private func play(
        patter: (figure: Figure, player: CharacterPlayer, clip: Clip),
        patted: (figure: Figure, player: CharacterPlayer, clip: Clip),
        now: Date, landed: @escaping @MainActor () -> Void, finished: @escaping @MainActor () -> Void
    ) {
        let contact = PlaceholderCharacter.patContact
        let duration = max(patter.clip.duration, contact + patted.clip.duration)
        let current = Pat(patter: patter.figure, patted: patted.figure, start: now, duration: duration)
        pat = current
        try? patter.player.play(patter.clip, now: now)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.dotLands))
            landed()
            try? await Task.sleep(for: .seconds(contact - Self.dotLands))
            try? patted.player.play(patted.clip, now: now.addingTimeInterval(contact))
            try? await Task.sleep(for: .seconds(duration - contact))
            guard let self, self.pat == current else { return }
            self.pat = nil
            finished()
        }
    }

    // MARK: Helpers

    private func nextBubble() -> Int {
        bubbles += 1
        return bubbles
    }

    private func show(_ new: Bubble, for seconds: Double) {
        bubble = new
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            if self?.bubble?.id == new.id { self?.bubble = nil }
        }
    }

    /// What someone is up to today, as their latest post says it: the status, and a second line
    /// with the words they posted, else the approved home's line where there is one.
    static func status(
        _ status: StageStatus, eating: MealKind?, caption: String?, disclaimer: String?, asleep: Bool
    ) -> (title: String, detail: String?) {
        if asleep { return (String(copy: "睡着了", bundle: .module), nil) }
        switch (eating, status) {
        case (.healthyMeal?, _):
            return (String(copy: "在吃健康餐", bundle: .module), caption)
        case (.cheatMeal?, _):
            return (String(copy: "在吃放纵餐", bundle: .module), caption)
        case (nil, .trained(let activity?)):
            return (
                String(copy: "\(activity.localizedName) 中", bundle: .module),
                caption ?? String(copy: "今天训练", bundle: .module)
            )
        case (nil, .trained(nil)):
            return (String(copy: "今天训练", bundle: .module), caption)
        case (nil, .disclaimer):
            return (
                String(copy: "请假条", bundle: .module),
                disclaimer ?? String(copy: "请假了", bundle: .module)
            )
        case (nil, .restDay):
            return (
                String(copy: "休息日", bundle: .module),
                String(copy: "按计划休息", bundle: .module)
            )
        case (nil, .notYet):
            return (String(copy: "今天还没打卡", bundle: .module), nil)
        }
    }
}
#endif
