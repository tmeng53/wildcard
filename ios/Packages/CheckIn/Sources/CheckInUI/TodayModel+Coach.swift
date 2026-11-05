#if os(iOS)
import CheckInDomain
import Contracts
import Foundation

/// The coach on the home's sideline: a tap starts its pep talk and pops up its card, with its
/// 战术板 line of the day over it (Tracy, 2026-11-05; no bubble from a tap).
extension TodayModel {
    /// The coach's 战术板 line while its day lasts, for its card and its 简历.
    public var coachLine: CoachNote? { store.coachLine }

    /// The coach was tapped: it gives its pep talk and its card opens.
    func tapCoach() {
        guard arrival == nil else { return }
        cast.coachTalks()
        openCoach()
    }
}
#endif
