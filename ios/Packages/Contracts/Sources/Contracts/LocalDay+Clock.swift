import Foundation

extension LocalDay {
    /// A day lasts until this hour of the next morning, so a late workout logged after midnight
    /// counts for the day it was done. The API's rule; it refuses a check-in for any other day.
    public static let graceHours = 3

    /// The member's day at `moment` on the wall clock of `timeZone`: before 3am it is still the
    /// day before.
    public init(at moment: Date, in timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        // The wall clock's hour, not three hours earlier: the two differ on the nights clocks change.
        let parts = calendar.dateComponents([.year, .month, .day, .hour], from: moment)
        // A Gregorian calendar always gives a real year, month and day for a real moment.
        let calendarDay = Self.unchecked(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
        self = (parts.hour ?? 0) < Self.graceHours ? calendarDay.adding(days: -1) : calendarDay
    }

    /// The day `count` days later, or earlier when negative.
    public func adding(days count: Int) -> LocalDay {
        let calendar = Self.utc
        guard let date = calendar.date(byAdding: .day, value: count, to: midnight) else {
            fatalError("a day \(count) days from \(self) is always a real day")
        }
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return Self.unchecked(year: parts.year ?? year, month: parts.month ?? month, day: parts.day ?? day)
    }

    /// Monday is 1, Sunday 7, as weeks run Monday to Sunday.
    public var weekday: Int {
        let sundayFirst = Self.utc.component(.weekday, from: midnight)
        return sundayFirst == 1 ? 7 : sundayFirst - 1
    }

    /// The Monday of this day's week: the week weekly plans and 本周 count in.
    public var weekStart: LocalDay { adding(days: 1 - weekday) }

    /// The ISO week of the year, as in 「第 42 周」.
    public var weekOfYear: Int {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = Self.utc.timeZone
        return calendar.component(.weekOfYear, from: midnight)
    }

    /// The day's start in UTC, where the calendar arithmetic above runs.
    private var midnight: Date {
        guard let date = Self.utc.date(from: DateComponents(year: year, month: month, day: day)) else {
            fatalError("\(self) is a real day, so it has a date")
        }
        return date
    }

    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    /// For parts a calendar just produced.
    private static func unchecked(year: Int, month: Int, day: Int) -> LocalDay {
        LocalDay(calendarYear: year, month: month, day: day)
    }
}
