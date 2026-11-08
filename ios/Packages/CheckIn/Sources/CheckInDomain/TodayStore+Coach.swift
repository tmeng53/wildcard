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
        do {
            loadedCoach = (home.squad.id, try await backend.coach(in: home.squad.id))
        } catch {}
        await loadCoachNotes(in: home)
    }

    /// The coach's morning notes waiting for the member, from their squad (one squad a member).
    private func loadCoachNotes(in home: Home) async {
        guard let found = try? await backend.coachNotes(in: [home.squad.id]) else { return }
        coachNotes = found
    }

    /// Whether a note waits unseen, for the dot on the coach's phone; seeing it on the coach's
    /// page puts it away on the server, and the next load clears the dot.
    public var hasWaitingNote: Bool { !coachNotes.isEmpty }

    /// The 战术板 line the coach says on the home now, while its day lasts.
    public var coachLine: CoachNote? { coach?.line(at: now()) }
}
