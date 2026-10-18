import Contracts
import Foundation

/// Which day a moment belongs to. A day ends at midnight in the member's own time
/// zone, but anything before 3am still counts for the day before, so a late workout
/// logged after midnight lands on the day it was done.
public enum DayBoundary {
    /// Hours after midnight that still count for the previous day.
    public static let graceHours = 3

    /// The member's day at `moment`, read on the wall clock of `timeZone` (the
    /// device's zone when they check in).
    public static func day(at moment: Timestamp, in timeZone: TimeZone) throws(CheckInError) -> LocalDay {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour], from: moment.date)
        guard let year = parts.year, let month = parts.month, let day = parts.day, let hour = parts.hour,
            let calendarDay = try? LocalDay(year: year, month: month, day: day)
        else { throw .dayOutOfRange }
        return hour < graceHours ? try calendarDay.adding(days: -1) : calendarDay
    }
}

/// Monday to Sunday, numbered as in ISO 8601.
public enum Weekday: Int, CaseIterable, Hashable, Sendable {
    case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday
}

extension LocalDay {
    /// The day `count` days later (earlier when negative).
    public func adding(days count: Int) throws(CheckInError) -> LocalDay {
        let (year, month, day) = Self.civil(fromDayNumber: dayNumber + count)
        guard let result = try? LocalDay(year: year, month: month, day: day) else { throw .dayOutOfRange }
        return result
    }

    public var weekday: Weekday {
        // 1970-01-01 was a Thursday.
        let index = ((dayNumber % 7) + 7 + 3) % 7  // 0 = Monday
        return Weekday(rawValue: index + 1) ?? .monday
    }

    /// Days since 1970-01-01, using the proleptic Gregorian calendar.
    var dayNumber: Int {
        // Howard Hinnant's days_from_civil: https://howardhinnant.github.io/date_algorithms.html
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    private static func civil(fromDayNumber number: Int) -> (year: Int, month: Int, day: Int) {
        // Howard Hinnant's civil_from_days, the inverse of `dayNumber`.
        let z = number + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let dayOfEra = z - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let shiftedMonth = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * shiftedMonth + 2) / 5 + 1
        let month = shiftedMonth < 10 ? shiftedMonth + 3 : shiftedMonth - 9
        return (yearOfEra + era * 400 + (month <= 2 ? 1 : 0), month, day)
    }
}
