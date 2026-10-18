import Contracts

/// Seven days in a row, starting on the member's own week-start day.
public struct Week: Hashable, Sendable {
    public let start: LocalDay
    /// Exactly seven days, `start` first.
    public let days: [LocalDay]

    public init(startingOn start: LocalDay) throws(CheckInError) {
        var days = [start]
        for offset in 1..<7 { days.append(try start.adding(days: offset)) }
        self.start = start
        self.days = days
    }

    /// The week `day` falls in, for a member whose week starts on `weekStart`.
    public static func containing(_ day: LocalDay, weekStartsOn weekStart: Weekday) throws(CheckInError) -> Week {
        let offset = (day.weekday.rawValue - weekStart.rawValue + 7) % 7
        return try Week(startingOn: try day.adding(days: -offset))
    }

    public func contains(_ day: LocalDay) -> Bool {
        days.contains(day)
    }
}
