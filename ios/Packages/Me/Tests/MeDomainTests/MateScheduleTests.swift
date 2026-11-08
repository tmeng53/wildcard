import Contracts
import MeDomain
import Testing

struct MateScheduleTests {
    /// 今天 is their day on their calendar, not the viewer's: a Shanghai member already on Monday
    /// while a Los Angeles viewer is still on Sunday.
    @Test func todayFollowsTheirCalendar() throws {
        let monday = try LocalDay("2026-11-09")
        let viewersSunday = try LocalDay("2026-11-08")
        let schedule = try week(from: monday, today: monday)
        #expect(schedule.todayIndex(else: viewersSunday) == 0)
        let (theirThursday, viewersWednesday) = (try LocalDay("2026-11-12"), try LocalDay("2026-11-11"))
        let thursday = try week(from: monday, today: theirThursday)
        #expect(thursday.todayIndex(else: viewersWednesday) == 3)
    }

    /// An older server sends no today, and the viewer's day stands in; none is shaded when it
    /// falls outside the week.
    @Test func olderServersFallBackToTheViewersDay() throws {
        let monday = try LocalDay("2026-11-09")
        let (wednesday, lastSunday) = (try LocalDay("2026-11-11"), try LocalDay("2026-11-08"))
        let schedule = try week(from: monday, today: nil)
        #expect(schedule.todayIndex(else: wednesday) == 2)
        #expect(schedule.todayIndex(else: lastSunday) == nil)
    }

    private func week(from monday: LocalDay, today: LocalDay?) throws -> MateSchedule {
        try MateSchedule(
            weekStart: monday, days: Array(repeating: .rest, count: 7), marks: Array(repeating: .none, count: 7),
            fuel: [], firstWeek: monday, today: today)
    }
}
