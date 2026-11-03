import Contracts
import Foundation

extension TodayStore {
    /// The squad's coach on the sideline, as last loaded; nil while the squad has none, or
    /// before it is loaded for the squad on the home.
    public var coach: SidelineCoach? {
        guard let loadedCoach, loadedCoach.squad == savedHome?.squad.id else { return nil }
        return loadedCoach.coach
    }

    /// Loads the squad's coach and its line; keeps what was shown when the server can't be
    /// reached.
    public func loadCoach() async {
        guard let squad = savedHome?.squad.id, phase == .current else { return }
        do {
            loadedCoach = (squad, try await backend.coach(in: squad))
        } catch {}
    }

    /// The 战术板 line the coach says on the home now, while its day lasts.
    public var coachLine: CoachNote? { coach?.line(at: now()) }
}
