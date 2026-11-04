/// The days every year a limited scene is open (冬季限定), and its store with it: `start` to
/// `end`, both included, in New York time, running over New Year when `end` comes before
/// `start`. From the scenes list (`GET /public/catalog`, `scenes`); the app never shows the dates.
public struct SceneSeason: Hashable, Sendable {
    public let start: MonthDay
    public let end: MonthDay

    public init(start: MonthDay, end: MonthDay) {
        (self.start, self.end) = (start, end)
    }

    /// Whether `day` falls in the season.
    public func contains(_ day: LocalDay) -> Bool {
        let today = MonthDay(month: day.month, day: day.day)
        return start <= end ? start <= today && today <= end : today >= start || today <= end
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
