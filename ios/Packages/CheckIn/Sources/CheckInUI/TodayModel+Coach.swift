#if os(iOS)
import CheckInDomain
import Contracts
import Foundation

/// The coach on the home's sideline: a tap cheers it and opens its 简历, where its 战术板 line
/// of the day is pinned (Tracy, 2026-11-04: no bubble from a tap).
extension TodayModel {
    /// The coach's 战术板 line while its day lasts, for its 简历.
    public var coachLine: CoachNote? { store.coachLine }

    /// The coach's morning note (便条) on 今天 now, once the scene is free for it: not while a
    /// check-in is being written, the burst is open or the squad is dropping in.
    var coachNote: CoachMemberNote? {
        guard step == .scene, !isBurstOpen, arrival == nil else { return nil }
        return store.coachNote
    }

    /// The member's nickname, for whom the note is.
    var noteReader: String? { home?.mine?.character?.nickname.text }

    /// 收下: the note goes, and the next squad's (if any) follows.
    func putAwayNote() {
        Task { await store.putAwayNote() }
    }

    /// Shows a morning note again, from its row in 通知.
    public func showAgain(_ note: CoachMemberNote) {
        store.showAgain(note)
    }

    /// The coach was tapped: it cheers and its 简历 opens.
    func tapCoach() {
        guard arrival == nil else { return }
        cast.cheerCoach()
        openCoach()
    }
}
#endif
