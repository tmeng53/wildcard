/// A global switch from the catalog (`GET /public/catalog`, `switches`): one turns many things on
/// or off together, such as the winter switch that opens the 雪场 scene and its store. A scheduled
/// one is on every year from `start` to `end`, both included, in New York time, running over New
/// Year when `end` comes before `start`. The app never shows the dates.
public enum CatalogSwitch: Hashable, Sendable {
    case alwaysOn
    case alwaysOff
    case schedule(start: MonthDay, end: MonthDay)

    /// Whether the switch is on on `day`.
    public func isOn(_ day: LocalDay) -> Bool {
        switch self {
        case .alwaysOn: return true
        case .alwaysOff: return false
        case .schedule(let start, let end):
            let today = MonthDay(month: day.month, day: day.day)
            return start <= end ? start <= today && today <= end : today >= start || today <= end
        }
    }
}

/// A day of the year, `MM-DD`.
public struct MonthDay: Hashable, Comparable, Sendable {
    public let month: Int
    public let day: Int

    public init(month: Int, day: Int) {
        (self.month, self.day) = (month, day)
    }

    /// `MM-DD`; nil for anything else.
    public init?(_ text: String) {
        let parts = text.split(separator: "-")
        guard parts.count == 2, parts.allSatisfy({ $0.count == 2 }), let month = Int(parts[0]),
            let day = Int(parts[1]), (1...12).contains(month), (1...31).contains(day)
        else { return nil }
        self.init(month: month, day: day)
    }

    public static func < (lhs: MonthDay, rhs: MonthDay) -> Bool {
        (lhs.month, lhs.day) < (rhs.month, rhs.day)
    }
}
