import Contracts
import Foundation
import Testing

// The same moments as the API's `localDayAt` tests, so the app picks the day the API checks.
@Test(arguments: [
    // 2026-10-19 08:00 UTC is 01:00 in Los Angeles: still Sunday the 18th.
    ("2026-10-19T08:00:00.000Z", "America/Los_Angeles", "2026-10-18"),
    // 03:00 there: Monday has begun.
    ("2026-10-19T10:00:00.000Z", "America/Los_Angeles", "2026-10-19"),
    ("2026-10-19T09:59:59.999Z", "America/Los_Angeles", "2026-10-18"),
    ("2026-10-19T02:59:00.000Z", "UTC", "2026-10-18"),
    ("2026-10-19T03:00:00.000Z", "UTC", "2026-10-19"),
    // 2026-10-19 00:30 UTC is 08:30 in Shanghai.
    ("2026-10-19T00:30:00.000Z", "Asia/Shanghai", "2026-10-19"),
    // The night US clocks fall back (2026-11-01, 02:00 → 01:00): 02:30 PST is 10:30 UTC.
    ("2026-11-01T10:30:00.000Z", "America/Los_Angeles", "2026-10-31"),
    ("2026-11-01T11:00:00.000Z", "America/Los_Angeles", "2026-11-01"),
])
func theDayLastsUntilThreeOnTheWallClock(moment: String, zone: String, day: String) throws {
    let timeZone = try #require(TimeZone(identifier: zone))
    #expect(LocalDay(at: try Timestamp(moment).date, in: timeZone).description == day)
}

@Test func addsDaysAcrossMonthsAndYears() throws {
    #expect(try LocalDay("2026-12-31").adding(days: 1).description == "2027-01-01")
    #expect(try LocalDay("2024-03-01").adding(days: -1).description == "2024-02-29")
    #expect(try LocalDay("2026-10-19").adding(days: 0).description == "2026-10-19")
}

@Test func weeksRunMondayToSunday() throws {
    #expect(try LocalDay("2026-10-19").weekday == 1)
    #expect(try LocalDay("2026-10-25").weekday == 7)
    #expect(try LocalDay("2026-10-25").weekStart.description == "2026-10-19")
    #expect(try LocalDay("2026-10-19").weekStart.description == "2026-10-19")
    #expect(try LocalDay("2027-01-01").weekStart.description == "2026-12-28")
}

@Test func numbersTheWeekFromTheFirstOne() throws {
    let joined = try LocalDay("2026-10-22")
    #expect(try LocalDay("2026-10-19").weekNumber(since: joined) == 1)
    #expect(try LocalDay("2026-10-25").weekNumber(since: joined) == 1)
    #expect(try LocalDay("2026-10-26").weekNumber(since: joined) == 2)
    #expect(try LocalDay("2027-01-04").weekNumber(since: joined) == 12)
    #expect(try LocalDay("2026-10-12").weekNumber(since: joined) == 1)
}
