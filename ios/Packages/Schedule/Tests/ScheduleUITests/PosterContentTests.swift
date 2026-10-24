import Contracts
import Foundation
import ScheduleDomain
import Testing

@testable import ScheduleUI

/// What each lane and the poster's corners show, from the week and what the member holds.
struct PosterContentTests {
    private let monday = Self.day("2026-10-19")
    private let thursday = Self.day("2026-10-22")
    private let plan: [PlanDay] = [
        .train(.sport(.run)), .train(.sport(.tennis)), .rest, .train(.sport(.strength)), .train(.sport(.run)), .rest,
        .train(.sport(.tennis)),
    ]
    private let titles = [AwardTitle(title: "网球担当", speech: "三次站上网球场")]

    private static func day(_ text: String) -> LocalDay {
        guard let day = try? LocalDay(text) else { fatalError("\(text) is not a day") }
        return day
    }

    private func sheet(_ weekStart: LocalDay) throws -> WeekSheet {
        try WeekSheet(
            weekStart: weekStart, plan: plan, marks: [.trained, .disclaimer, .none, .trained, .none, .none, .none],
            titles: titles, squad: SquadCount(trained: 14, planned: 22), fuel: [.suggested(.water)])
    }

    @Test func thisWeekShadesTodayAndCountsTrainedDays() throws {
        let board = WeekBoard(weekStart: monday, days: plan, today: thursday)
        let content = PosterContent(
            sheet: try sheet(monday), board: board, nickname: "Tracy", weekNumber: 3, fuelOpen: true)
        #expect(content.lanes.map(\.look) == [.plain, .plain, .plain, .today, .plain, .plain, .plain])
        #expect(content.lanes.map(\.isEditable) == [false, false, false, true, true, true, true])
        #expect(content.tally == .trained(2, planned: 5, isPast: false))
        #expect(content.titles.isEmpty, "titles wait for the week's awards")
        #expect(content.fuelOpen, "this week's goals open too")
        #expect(content.fuelEditable)
        #expect(content.weekEnd == Self.day("2026-10-25"))
    }

    @Test func aSelectedDayThisWeekIsHeld() throws {
        var board = WeekBoard(weekStart: monday, days: plan, today: thursday)
        board.tap(5)
        let content = PosterContent(
            sheet: try sheet(monday), board: board, nickname: "Tracy", weekNumber: 3, fuelOpen: false)
        #expect(content.lanes.map(\.look) == [.plain, .plain, .plain, .today, .plain, .held, .plain])
    }

    @Test func nextWeekCountsThePlanAndOpensItsGoals() throws {
        let next = monday.adding(days: 7)
        var board = WeekBoard(weekStart: next, days: plan, today: thursday)
        board.tap(2)
        let content = PosterContent(
            sheet: try sheet(next), board: board, nickname: "Tracy", weekNumber: 3, fuelOpen: true)
        #expect(content.tally == .planned(train: 5, rest: 2))
        #expect(content.lanes[2].look == .held)
        #expect(content.fuelOpen)
        #expect(content.fuelEditable)
    }

    @Test func aPastWeekShowsItsTitles() throws {
        let last = monday.adding(days: -7)
        let board = WeekBoard(weekStart: last, days: plan, today: thursday)
        let content = PosterContent(
            sheet: try sheet(last), board: board, nickname: "Tracy", weekNumber: 3, fuelOpen: true)
        #expect(content.titles == titles)
        #expect(content.tally == .trained(2, planned: 5, isPast: true))
        #expect(!content.fuelOpen)
        #expect(content.lanes.allSatisfy { !$0.isEditable })
    }

    @Test func aGoalBeingTypedShowsOnThePoster() throws {
        let next = monday.adding(days: 7)
        let board = WeekBoard(weekStart: next, days: plan, today: thursday)
        let typing = PosterContent(
            sheet: try sheet(next), board: board, nickname: "Tracy", weekNumber: 3, fuelOpen: true, typingFuel: " 少喝咖啡 "
        )
        #expect(typing.fuel.last == .own("少喝咖啡"))
        let blank = PosterContent(
            sheet: try sheet(next), board: board, nickname: "Tracy", weekNumber: 3, fuelOpen: true, typingFuel: "  ")
        #expect(blank.fuel == (try sheet(next)).fuel)
    }

    @Test func theSavedPictureHoldsNothing() throws {
        let last = monday.adding(days: -7)
        var board = WeekBoard(weekStart: monday, days: plan, today: thursday)
        board.tap(5)
        let held = PosterContent(
            sheet: try sheet(monday), board: board, nickname: "Tracy", weekNumber: 3, fuelOpen: false
        ).forSaving
        #expect(held.lanes.map(\.look) == [.plain, .plain, .plain, .today, .plain, .plain, .plain])
        #expect(held.lanes.allSatisfy { !$0.isEditable })
        let award = PosterContent(
            sheet: try sheet(last), board: WeekBoard(weekStart: last, days: plan, today: thursday), nickname: "Tracy",
            weekNumber: 3,
            fuelOpen: false
        ).forSaving
        #expect(award.titles == titles, "the stickers stay on the picture")
    }
}

/// The in-memory member keeps the API's rules, so the screen behaves the same on it.
struct InMemoryScheduleBackendTests {
    private let losAngeles = TimeZone(identifier: "America/Los_Angeles") ?? .gmt

    /// Thursday 2026-10-22, noon in Los Angeles.
    private var thursday: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = losAngeles
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 12)) ?? .now
    }

    @Test func theSampleRunsFromFiveWeeksBackToNextWeek() async throws {
        let backend = InMemoryScheduleBackend.sample(now: thursday, timeZone: losAngeles)
        let profile = try await backend.profile()
        #expect(profile.firstWeek.description == "2026-09-14")
        let last = try await backend.week(starting: profile.firstWeek.adding(days: 28))
        #expect(!last.titles.isEmpty, "a week that is over has titles")
        let this = try await backend.week(starting: profile.firstWeek.adding(days: 35))
        #expect(this.titles.isEmpty)
        #expect(this.marks[3] == .trained, "today is trained")
        #expect(this.marks[4...].allSatisfy { $0 == .none }, "nothing is marked ahead of today")
        #expect(try await backend.trainedDays() == 46)
    }

    @Test func thisWeekKeepsItsStartedDaysAndChangesTheRest() async throws {
        let backend = InMemoryScheduleBackend.sample(now: thursday, timeZone: losAngeles)
        let monday = LocalDay(at: thursday, in: losAngeles).weekStart
        var plan = try await backend.week(starting: monday).plan
        let original = plan
        plan[0] = .rest
        await #expect(throws: ScheduleError.dayStarted) { try await backend.savePlan(plan, weekStart: monday) }
        plan = original
        plan[4] = .rest
        #expect(try await backend.savePlan(plan, weekStart: monday) == plan)
        await #expect(throws: ScheduleError.weekOver) {
            try await backend.savePlan(original, weekStart: monday.adding(days: -7))
        }
        await #expect(throws: ScheduleError.weekOver) {
            try await backend.saveFuel([.suggested(.water)], weekStart: monday.adding(days: -7))
        }
        try await backend.saveFuel([.suggested(.water)], weekStart: monday)
        try await backend.saveFuel([.suggested(.veggies)], weekStart: monday.adding(days: 7))
        #expect(try await backend.week(starting: monday.adding(days: 7)).fuel == [.suggested(.veggies)])
    }
}
