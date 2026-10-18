import CheckInDomain
import Contracts
import Foundation
import Testing

private let toronto = TimeZone(identifier: "America/Toronto")!
private let vancouver = TimeZone(identifier: "America/Vancouver")!

private func at(_ text: String) -> Timestamp { try! Timestamp(text) }

@Test func dayChangesAtThreeInTheMorningNotMidnight() throws {
    // 2026-10-18 is EDT (UTC-4) in Toronto.
    #expect(try DayBoundary.day(at: at("2026-10-19T03:59:00Z"), in: toronto) == day("2026-10-18"))  // 23:59
    #expect(try DayBoundary.day(at: at("2026-10-19T06:59:59Z"), in: toronto) == day("2026-10-18"))  // 02:59:59
    #expect(try DayBoundary.day(at: at("2026-10-19T07:00:00Z"), in: toronto) == day("2026-10-19"))  // 03:00
}

@Test func theSameMomentIsADifferentDayInAnotherZone() throws {
    // 02:00 Oct 19 in Toronto is 23:00 Oct 18 in Vancouver; both count for Oct 18.
    // 04:00 in Toronto is 01:00 in Vancouver: Toronto has moved on, Vancouver hasn't.
    #expect(try DayBoundary.day(at: at("2026-10-19T08:00:00Z"), in: toronto) == day("2026-10-19"))
    #expect(try DayBoundary.day(at: at("2026-10-19T08:00:00Z"), in: vancouver) == day("2026-10-18"))
}

@Test func graceReadsTheWallClockAcrossTheSpringForward() throws {
    // 2026-03-08: Toronto clocks jump from 02:00 to 03:00 EDT. 03:30 EDT is 07:30Z.
    #expect(try DayBoundary.day(at: at("2026-03-08T07:30:00Z"), in: toronto) == day("2026-03-08"))
    // 01:30 EST, before the jump, still counts for the 7th.
    #expect(try DayBoundary.day(at: at("2026-03-08T06:30:00Z"), in: toronto) == day("2026-03-07"))
}

@Test func graceCrossesMonthAndYearEnds() throws {
    let utc = TimeZone(identifier: "UTC")!
    #expect(try DayBoundary.day(at: at("2027-01-01T01:00:00Z"), in: utc) == day("2026-12-31"))
    #expect(try DayBoundary.day(at: at("2028-03-01T02:00:00Z"), in: utc) == day("2028-02-29"))
}

@Test func addsDaysAcrossLeapYears() throws {
    #expect(try day("2028-02-28").adding(days: 1) == day("2028-02-29"))
    #expect(try day("2026-02-28").adding(days: 1) == day("2026-03-01"))
    #expect(try day("2026-12-31").adding(days: 1) == day("2027-01-01"))
    #expect(try day("2026-01-01").adding(days: -1) == day("2025-12-31"))
    #expect(try day("2000-03-01").adding(days: -1) == day("2000-02-29"))
}

@Test func addingPastTheSupportedYearsThrows() {
    #expect(throws: CheckInError.dayOutOfRange) { try day("1970-01-01").adding(days: -1) }
}

@Test func knowsTheWeekday() {
    #expect(day("2026-10-18").weekday == .sunday)
    #expect(day("2026-10-19").weekday == .monday)
    #expect(day("1970-01-01").weekday == .thursday)
    #expect(day("2028-02-29").weekday == .tuesday)
}
