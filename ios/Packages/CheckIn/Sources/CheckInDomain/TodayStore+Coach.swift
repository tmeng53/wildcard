import Contracts
import Foundation

extension TodayStore {
    /// The squad's coach on the sideline, as last loaded; nil while the squad has none, or
    /// before it is loaded for the squad on the home.
    public var coach: SidelineCoach? {
        guard let loadedCoach, loadedCoach.squad == savedHome?.squad.id else { return nil }
        return loadedCoach.coach
    }

    /// Whether the squad on the home is known to have no coach, so its sideline is free for one:
    /// false before its coach is loaded, or when that load failed.
    public var isHiringCoach: Bool {
        guard let loadedCoach, loadedCoach.squad == savedHome?.squad.id else { return false }
        return loadedCoach.coach == nil
    }

    /// Loads the squad's coach and its line; keeps what was shown when the server can't be
    /// reached.
    public func loadCoach() async {
        guard let home = savedHome, phase == .current else { return }
        await loadOpenedLetter()
        do {
            loadedCoach = (home.squad.id, try await backend.coach(in: home.squad.id))
        } catch {}
        await loadCoachNotes(in: home)
    }

    /// The coach's morning notes waiting for the member, from their squad (one squad a member).
    private func loadCoachNotes(in home: Home) async {
        if openedNote == nil { openedNote = await backend.openedNote() }
        guard let found = try? await backend.coachNotes(in: [home.squad.id]) else { return }
        coachNotes = found.filter { !putAway.contains($0.id) }
        // A push tapped for a note no longer waiting doesn't open a later one by itself.
        if coachNotes.isEmpty { showsWaitingNote = false }
    }

    /// The note on 今天 now, if any: one shown again from 通知, else the first waiting once the
    /// member opened it. None shows by itself.
    public var coachNote: CoachMemberNote? { noteAgain ?? (showsWaitingNote ? coachNotes.first : nil) }

    /// 收下: the note on 今天 goes, the next (if any) follows, and the server remembers it so no
    /// phone shows it again. When the server can't be reached, it stays put away on this phone
    /// until the app is next launched.
    public func putAwayNote() async {
        guard let note = coachNote else { return }
        noteAgain = nil
        showsWaitingNote = false
        coachNotes.removeAll { $0.id == note.id }
        putAway.insert(note.id)
        openedNote = note
        try? await backend.putAway(note)
    }

    /// Shows a note again from 通知, before any other waiting.
    public func showAgain(_ note: CoachMemberNote) {
        noteAgain = note
    }

    /// Today's note the member already put away, which the coach's card opens again (今天给你的消息);
    /// nil while none is, or one is open or waiting, which a tap on the coach opens instead.
    public var todaysNote: CoachMemberNote? {
        guard let note = openedNote, coachNote == nil, coachNotes.isEmpty, note.squad == savedHome?.squad.id,
            note.day == LocalDay(at: now(), in: CoachNote.timeZone)
        else { return nil }
        return note
    }

    /// Whether a note waits unread while none is open, for the dot on the coach's phone.
    public var hasWaitingNote: Bool { coachNote == nil && !coachNotes.isEmpty }

    /// Shows the newest waiting note, as soon as it is loaded: a tap on the coach or on its push.
    public func showWaitingNote() {
        showsWaitingNote = true
    }

    /// The 战术板 line the coach says on the home now, while its day lasts.
    public var coachLine: CoachNote? { coach?.line(at: now()) }
}
