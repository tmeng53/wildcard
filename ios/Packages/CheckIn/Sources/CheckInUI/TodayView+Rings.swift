#if os(iOS)
import CheckInDomain
import Contracts
import DesignSystemUI
import SportsUI

extension TodayView {
    /// Everyone's ring on the squad card's 今天 row, in the home's order.
    func squadMembers(_ home: Home) -> [SquadMember] {
        home.today.members.map { mate in
            SquadMember(
                id: mate.member.description,
                status: StageStatus(training: mate.training, activity: nil, plannedRest: mate.plannedRest).ring,
                isMe: mate.member == home.member,
                accessibilityIdentifier: mate.member == home.member ? "today.myRing" : "today.mateRing",
                badge: ringBadge(of: mate, home: home))
        }
    }

    /// What a teammate did today, on the badge at their ring's foot: the sport of their latest
    /// 练了, or a note for a 请假条 (Tracy, 2026-11-13).
    private func ringBadge(of mate: SquadmateToday, home: Home) -> String? {
        switch mate.training {
        case .trained: home.todaysSport(of: mate.member)?.symbol ?? Sport.generalSymbol
        case .disclaimer: Self.disclaimerBadge
        case .notCheckedIn: nil
        }
    }

    /// A 请假条's badge: a note, never the moon a rest day wears.
    private static let disclaimerBadge = "doc.text.fill"
}
#endif
