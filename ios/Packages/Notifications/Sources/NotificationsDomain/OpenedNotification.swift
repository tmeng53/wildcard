import Contracts
import Foundation

/// What a tapped notification opens, read from its payload's `aps.category` and `event`: the same
/// place its notice in 通知 and the home's banner open (`Notice.destination`), so a push, a 通知
/// row and a banner about one thing never go to two places.
public enum OpenedNotification: Hashable, Sendable {
    /// Where its notice goes.
    case open(AppDestination)
    /// A push this build can't read: the app opens 今天.
    case other

    /// - Parameters:
    ///   - category: the payload's `aps.category`, its notice's kind.
    ///   - event: the payload's `event`; values that aren't text are left out.
    public init(category: String?, event: [String: String]) {
        self = Self.subject(category: category, event: event).flatMap(\.destination).map(Self.open) ?? .other
    }

    /// The notice a push tells, as far as `Notice.destination` reads it.
    private static func subject(category: String?, event: [String: String]) -> Notice? {
        let told = Date(timeIntervalSince1970: 0)
        switch category {
        case "dailyProgress":
            return Notice(
                id: NoticeID(rawValue: 0), toldAt: told, squad: nil, subject: .dailyProgress(PushAlert(key: "")))
        case "weeklyAwards":
            guard let squad = event["squad"].flatMap(UUID.init(uuidString:)),
                let week = event["weekStart"].flatMap({ try? LocalDay($0) })
            else { return nil }
            return Notice(
                id: NoticeID(rawValue: 0), toldAt: told, squad: SquadID(squad),
                subject: .weeklyAwards(PushAlert(key: ""), week: week))
        case "comment":
            guard let checkIn = event["checkIn"].flatMap(UUID.init(uuidString:)) else { return nil }
            return Notice(
                id: NoticeID(rawValue: 0), toldAt: told, squad: nil,
                subject: .comment(PushAlert(key: ""), checkIn: CheckInID(checkIn)))
        default:
            return nil
        }
    }
}
