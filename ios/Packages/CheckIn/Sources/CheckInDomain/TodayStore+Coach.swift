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
        await loadChallenge(in: home)
    }

    private func loadChallenge(in home: Home) async {
        guard let found = try? await backend.todayChallenge(in: home.squad.id) else { return }
        loadedChallenge = (home.squad.id, found)
    }

    /// The day's challenge the member accepted, while its day lasts, for 我的一周 (Tracy,
    /// 2026-11-08): with 我完成了 until it is done. Nil for one declined or not yet answered.
    public var acceptedChallenge: DayChallenge? {
        guard let loadedChallenge, loadedChallenge.squad == savedHome?.squad.id,
            let found = loadedChallenge.challenge, found.challenge.answer == .accepted, found.day == day
        else { return nil }
        return found
    }

    /// 我完成了: marks today's challenge done at once, and back as it was if the server refused.
    public func completeChallenge() async {
        guard let home = savedHome, let found = acceptedChallenge, found.challenge.completedBy == nil,
            !isCompletingChallenge
        else { return }
        isCompletingChallenge = true
        defer { isCompletingChallenge = false }
        loadedChallenge = (home.squad.id, found.completed(by: .member))
        do {
            let standing = try await backend.completeChallenge(found.note, in: home.squad.id)
            loadedChallenge = (home.squad.id, found.completed(by: standing))
        } catch {
            loadedChallenge = (home.squad.id, found)
        }
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
