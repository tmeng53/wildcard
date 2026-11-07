#if os(iOS)
import CheckInDomain
import Contracts
import Foundation

/// The coach on the home's sideline: a tap starts its pep talk and pops up its card, with its
/// 战术板 line of the day over it (Tracy, 2026-11-05; no bubble from a tap). While a morning note
/// waits, its phone shows a dot and buzzes, and a tap opens the note instead (Tracy, 2026-11-07).
extension TodayModel {
    /// The coach's 战术板 line while its day lasts, for its card and its 简历.
    public var coachLine: CoachNote? { store.coachLine }

    /// The coach's morning note (便条) the member opened, once the scene is free for it: not while
    /// a check-in is being written, the burst is open or the squad is dropping in.
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

    /// Whether the coach's phone shows its dot: a morning note waits and none is open.
    var coachHasNote: Bool { store.hasWaitingNote }

    /// Shows the newest waiting morning note, from a tap on its push.
    public func showWaitingNote() {
        store.showWaitingNote()
    }

    /// The coach was tapped: the waiting note opens, or else it gives its pep talk and its card opens.
    func tapCoach() {
        guard arrival == nil else { return }
        if store.hasWaitingNote { return store.showWaitingNote() }
        cast.coachTalks()
        openCoach()
    }
}
#endif
