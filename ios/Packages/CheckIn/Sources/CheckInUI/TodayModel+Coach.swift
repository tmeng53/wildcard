#if os(iOS)
import CheckInDomain
import Contracts
import Foundation

/// The coach on the home's sideline: a tap cheers it and opens its 简历, where its 战术板 line
/// of the day is pinned (Tracy, 2026-11-04: no bubble from a tap).
extension TodayModel {
    /// The coach's 战术板 line while its day lasts, for its 简历.
    public var coachLine: CoachNote? { store.coachLine }

    /// The coach was tapped: it cheers and its 简历 opens.
    func tapCoach() {
        guard arrival == nil else { return }
        cast.cheerCoach()
        openCoach()
    }
}
#endif
