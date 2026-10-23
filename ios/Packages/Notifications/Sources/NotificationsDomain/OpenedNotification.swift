import Contracts
import Foundation

/// What a tapped notification is about, read from its payload's `aps.category` and `event`, so
/// the app can open the screen it points at.
public enum OpenedNotification: Hashable, Sendable {
    /// The squad's Sunday 战报 for the week starting `week` is ready.
    case weeklyAwards(squad: SquadID, week: LocalDay)
    /// Anything else: the app opens 今天.
    case other

    /// - Parameters:
    ///   - category: the payload's `aps.category`.
    ///   - event: the payload's `event`; values that aren't text are left out.
    public init(category: String?, event: [String: String]) {
        switch category {
        case "weeklyAwards":
            guard let squad = event["squad"].flatMap(UUID.init(uuidString:)),
                let week = event["weekStart"].flatMap({ try? LocalDay($0) })
            else {
                self = .other
                return
            }
            self = .weeklyAwards(squad: SquadID(squad), week: week)
        default:
            self = .other
        }
    }
}
