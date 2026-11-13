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
        await loadUnseenCoachCards(in: home)
        await loadChallenge(in: home)
    }

    /// The server says which challenge is today's, on the squad's clock (which may differ from the
    /// member's), and none once it is gone; what was shown stays only while it can't be reached.
    func loadChallenge(in home: Home) async {
        do {
            loadedChallenge = (home.squad.id, try await backend.todayChallenge(in: home.squad.id))
        } catch {}
    }

    /// The day's challenge the member accepted, as the server last said, for 我的一周 (Tracy,
    /// 2026-11-08): with 我完成了 until it is done. Nil for one declined or not yet answered.
    public var acceptedChallenge: DayChallenge? {
        guard let loadedChallenge, loadedChallenge.squad == savedHome?.squad.id,
            let found = loadedChallenge.challenge, found.challenge.answer == .accepted
        else { return nil }
        return found
    }

    /// 我完成了: marks today's challenge done at once; if the server refused (its day may be over on
    /// the squad's clock), it is put back and read again.
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
            await loadChallenge(in: home)
        }
    }

    /// The coach's page's newest unseen card; what was shown stays while the server can't be
    /// reached.
    private func loadUnseenCoachCards(in home: Home) async {
        do {
            loadedUnseenCoachCard = (home.squad.id, try await backend.newestUnseenCoachCard(in: home.squad.id))
        } catch {}
    }

    /// The newest card on the coach's page the member hasn't seen, for its row on the squad card
    /// (Tracy, 2026-11-13): whatever the coach said, a note, the 战术板 line, a challenge or a gift.
    /// Swiping them away there marks them seen on the server, and the next load takes it away.
    public var newestUnseenCoachCard: CoachPageCard? {
        guard let loadedUnseenCoachCard, loadedUnseenCoachCard.squad == savedHome?.squad.id else { return nil }
        return loadedUnseenCoachCard.card
    }

    /// Whether the coach's page has a card the member hasn't seen, for the dot on its phone (Tracy,
    /// 2026-11-09).
    public var hasUnseenCoachCards: Bool { newestUnseenCoachCard != nil }

    /// The 战术板 line the coach says on the home now, while its day lasts.
    public var coachLine: CoachNote? { coach?.line(at: now()) }
}
