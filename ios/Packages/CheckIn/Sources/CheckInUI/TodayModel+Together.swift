#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import CheckInDomain
import Contracts
import Foundation
import UIKit

/// The squad celebrating together on the home (小人新动作, approved 2026-10-20): my stretch on
/// the day's first open, then at most one of 撞头, 叠罗汉 and 人浪 each time the home opens,
/// each kind once a day on this phone. Never at night, never over a check-in being made, and not
/// under Reduce Motion.
extension TodayModel {
    /// The key under which the kinds already played today are kept, apart for each account
    /// signed in on this phone: the day, then the kinds.
    private static func togetherKey(for member: MemberID) -> String {
        "today.together.\(member)"
    }

    /// The key under which the day I last stretched on is kept.
    private static func stretchKey(for member: MemberID) -> String {
        "today.stretched.\(member)"
    }

    /// How long after the home settles the stretch, then the celebration, start.
    static let togetherDelay = 0.6

    /// What the home plays once it has loaded, one after another: a notice, the news, pats on
    /// me, the coach's line, then the squad celebrating together.
    func playOpening() async {
        await showNextNotice()
        await tellNews()
        await playPatsOnMe()
        await sayCoachLine()
        await celebrateTogether()
    }

    /// Plays what the squad celebrates on this open, after the news and the pats on me.
    func celebrateTogether() async {
        guard together.isOn, let home = store.home, let day = home.mine?.day,
            !UIAccessibility.isReduceMotionEnabled
        else { return }
        try? await Task.sleep(for: .seconds(Self.togetherDelay))
        await untilArrived()
        guard isScenePlain else { return }
        if defaults.string(forKey: Self.stretchKey(for: home.member)) != day.description, stretchesInPose,
            let player, let clip = try? PlaceholderCharacter.clip(for: .stretch, persona: myPersona)
        {
            defaults.set(day.description, forKey: Self.stretchKey(for: home.member))
            try? player.play(clip)
            try? await Task.sleep(for: .seconds(clip.duration))
            guard isScenePlain else { return }
        }
        let shown = shownTogether(for: home.member, on: day)
        guard let mine = myMember else { return }
        guard
            let celebration = SquadCelebration.pick(
                myself: home.member, members: [mine] + cast.mates.map(\.member), squadWeek: home.today.squadWeek,
                shown: shown),
            together.play(celebration, myself: home.member, figures: togetherFigures())
        else { return }
        let kinds = (shown.map(\.rawValue) + [celebration.kind.rawValue]).sorted()
        defaults.set([day.description] + kinds, forKey: Self.togetherKey(for: home.member))
    }

    /// Whether my pose leaves room for the stretch: standing or training, not sitting, eating,
    /// holding my 请假条 up or asleep.
    private var stretchesInPose: Bool {
        switch myPose(at: stagePhase) {
        case .standing?, .inPlace?, .station?, nil: true
        case .sitting?, .holdingSign?, .eating?, .asleep?: false
        }
    }

    /// Nothing else is on the scene: no check-in being made, no pat, the lights not off.
    private var isScenePlain: Bool {
        step == .scene && !isBurstOpen && arrival == nil && pats.pat == nil && stagePhase != .night
    }

    /// The kinds already played today on this phone.
    private func shownTogether(for member: MemberID, on day: LocalDay) -> Set<SquadCelebration.Kind> {
        guard let kept = defaults.stringArray(forKey: Self.togetherKey(for: member)), kept.first == day.description
        else { return [] }
        return Set(kept.dropFirst().compactMap(SquadCelebration.Kind.init(rawValue:)))
    }

    /// Everyone who can join in, where they stand now: awake, not holding a 请假条 up and not
    /// eating, whose bowl or boba stays in their hands.
    private func togetherFigures() -> [PatStage.Figure: (
        player: CharacterPlayer, persona: Persona, spot: StagePosition
    )] {
        let seconds = Date.now.timeIntervalSinceReferenceDate
        var figures: [PatStage.Figure: (player: CharacterPlayer, persona: Persona, spot: StagePosition)] = [:]
        for mate in cast.mates {
            switch cast.stage.pose(of: mate.member, at: stagePhase) {
            case .holdingSign, .asleep, .eating: continue
            case .standing, .sitting, .station, .inPlace: break
            }
            guard let spot = cast.stage.position(of: mate.id, at: seconds) else { continue }
            figures[PatStage.Figure.mate(mate.id)] = (mate.player, mate.persona, spot)
        }
        // I join in as they do: not while holding my 请假条 up, asleep or eating.
        switch myPose(at: stagePhase) {
        case .holdingSign?, .asleep?, .eating?: break
        case .standing?, .sitting?, .station?, .inPlace?, nil:
            if let player { figures[PatStage.Figure.mine] = (player, myPersona, StagePosition.mine) }
        }
        return figures
    }
}
#endif
