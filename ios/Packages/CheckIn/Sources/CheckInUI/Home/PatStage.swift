#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import CheckInDomain
import Contracts
import DesignSystemUI
import Foundation
import Observation

/// 拍一拍 on the home scene (the approved C, 隔空拍). Tapping a teammate hops them and shows
/// what they're up to in a bubble with 「拍一拍」; patting jabs from where I stand, a graphite (brand) dot
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

    /// What a teammate's bubble is for.
    enum BubbleKind: Equatable {
        /// What they're up to today, after a tap.
        case status
        /// They just patted me.
        case pattedMe
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
    /// How long after opening the home a teammate pats me.
    nonisolated static let patMeDelay = 1.0
    /// A tapped teammate's hop: how long, and how high in the rig's points at the stage's
    /// scale of 0.25 (the approved home).
    nonisolated static let hop = (duration: 0.5, height: 14.0)

    // MARK: Tapping a teammate

    /// A teammate was tapped: they hop, cheer if awake and not mid-sport, and their bubble says
    /// what they're up to, with 「拍一拍」 (「拍过了」 once patted today). Tapped again while their
    /// bubble is up, the bubble closes.
    func tap(_ mate: SquadCast.Mate, cast: SquadCast, phase: DayPhase, now: Date = .now) {
        guard pat == nil else { return }
        if bubble?.mate == mate.id {
            bubble = nil
            return
        }
        hops[mate.id] = now
        let pose = cast.stage.pose(of: mate.member, at: phase)
        switch pose {
        case .standing, .sitting, .holdingSign:
            if let clip = try? PlaceholderCharacter.clip("cheer", persona: mate.persona, species: mate.species) {
                try? mate.player.play(clip, now: now)
            }
        case .station, .inPlace, .asleep:
            break
        }
        let line = Self.status(of: mate, pose: pose)
        show(
            Bubble(
                mate: mate.id, kind: .status, title: Self.titled(mate.name, line.title), detail: line.detail,
                id: nextBubble()), for: Self.bubbleHold)
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
            let name = mate.name ?? String(localized: "队友", bundle: .module.inAppLanguage)
            show(
                Bubble(
                    mate: mate.id, kind: .pattedMe,
                    title: String(localized: "\(name)拍了拍你", bundle: .module.inAppLanguage),
                    detail: others.first.map {
                        String(
                            localized: "\($0.name ?? String(localized: "队友", bundle: .module.inAppLanguage)) 也拍了拍你",
                            bundle: .module.inAppLanguage)
                    },
                    id: nextBubble()), for: Self.bubbleHold)
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

    /// 「小米 · 今天还没打卡」, or the status alone for someone without a nickname yet.
    static func titled(_ name: String?, _ status: String) -> String {
        guard let name else { return status }
        return String(localized: "\(name) · \(status)", bundle: .module.inAppLanguage)
    }

    /// What a teammate is up to today, as the approved home says it: the status, and a second
    /// line where there is one.
    static func status(of mate: SquadCast.Mate, pose: StagePose) -> (title: String, detail: String?) {
        if pose == .asleep { return (String(localized: "睡着了", bundle: .module.inAppLanguage), nil) }
        switch mate.member.status {
        case .trained(let activity?):
            return (
                String(localized: "\(activity.localizedName) 中", bundle: .module.inAppLanguage),
                String(localized: "今天练了", bundle: .module.inAppLanguage)
            )
        case .trained(nil):
            return (String(localized: "今天练了", bundle: .module.inAppLanguage), nil)
        case .disclaimer:
            return (
                String(localized: "请假条", bundle: .module.inAppLanguage),
                mate.disclaimer ?? String(localized: "今天休息", bundle: .module.inAppLanguage)
            )
        case .restDay:
            return (
                String(localized: "今天是休息日", bundle: .module.inAppLanguage),
                String(localized: "按计划休息", bundle: .module.inAppLanguage)
            )
        case .notYet:
            return (String(localized: "今天还没打卡", bundle: .module.inAppLanguage), nil)
        }
    }
}
#endif
