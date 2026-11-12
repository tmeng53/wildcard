import Contracts
import MeDomain
import Testing

struct MateScheduleTests {
    /// 今天 is their day on the squad's clock, not the viewer's: a Shanghai squad already on
    /// Monday while a Los Angeles viewer is still on Sunday.
    @Test func todayFollowsTheSquadsClock() throws {
        let monday = try LocalDay("2026-11-09")
        #expect(try week(from: monday, today: monday).todayIndex == 0)
        #expect(try week(from: monday, today: try LocalDay("2026-11-12")).todayIndex == 3)
    }

    /// A today outside the week shades no row.
    @Test func aTodayOutsideTheWeekShadesNone() throws {
        let monday = try LocalDay("2026-11-09")
        #expect(try week(from: monday, today: try LocalDay("2026-11-08")).todayIndex == nil)
    }

    private func week(from monday: LocalDay, today: LocalDay) throws -> MateSchedule {
        try MateSchedule(
            weekStart: monday, days: Array(repeating: .rest, count: 7), marks: Array(repeating: .none, count: 7),
            fuel: [], firstWeek: monday, today: today)
    }
}
