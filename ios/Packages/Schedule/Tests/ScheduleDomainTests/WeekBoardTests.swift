import Contracts
import Testing

@testable import ScheduleDomain

/// The rules for what a tap does on the poster, in each kind of week.
struct WeekBoardTests {
    /// Monday 2026-10-19: rest Wednesday and Saturday.
    private let monday = Fixtures.day("2026-10-19")
    private let plan = Fixtures.plan

    @Test func aWeekKnowsWhereItStandsFromToday() {
        let thursday = Fixtures.day("2026-10-22")
        #expect(WeekBoard(weekStart: monday, days: plan, today: thursday).tense == .current)
        #expect(WeekBoard(weekStart: monday, days: plan, today: thursday).today == 3)
        #expect(WeekBoard(weekStart: monday.adding(days: 7), days: plan, today: thursday).tense == .upcoming)
        #expect(WeekBoard(weekStart: monday.adding(days: -7), days: plan, today: thursday).tense == .past)
        // Sunday is still this week; Monday starts the next.
        #expect(WeekBoard(weekStart: monday, days: plan, today: Fixtures.day("2026-10-25")).tense == .current)
        #expect(WeekBoard(weekStart: monday, days: plan, today: Fixtures.day("2026-10-26")).tense == .past)
    }

    @Test func aPastWeekNeverChanges() {
        var board = WeekBoard(weekStart: monday, days: plan, today: Fixtures.day("2026-10-27"))
        for day in 0..<7 {
            #expect(board.tap(day) == .locked)
        }
        board.pick(.sport("swim"))
        #expect(board.days == plan)
        #expect(board.focus == .none)
    }

    @Test func thisWeekKeepsTheDaysBeforeToday() {
        var board = WeekBoard(weekStart: monday, days: plan, today: Fixtures.day("2026-10-22"))
        for day in 0...2 {
            #expect(board.tap(day) == .locked)
            #expect(!board.isEditable(day))
        }
        #expect(board.isEditable(4))
        #expect(board.tap(4) == .selected)
        #expect(board.focus == .selected(4))
    }

    @Test func todaysTrainingDayPicksAnotherSportOrRests() {
        var board = WeekBoard(weekStart: monday, days: plan, today: Fixtures.day("2026-10-22"))
        #expect(board.isEditable(3))
        #expect(board.tap(3) == .selected)
        board.pick(.sport("swim"))
        #expect(board.days[3] == .train(.sport("swim")))
        #expect(board.plannedDays == 5)
        board.rest()
        #expect(board.days[3] == .rest, "a rest today is a 休息日, no 请假条 needed")
        #expect(board.plannedDays == 4)
    }

    @Test func aRestTodayBecomesATrainingDay() {
        var board = WeekBoard(weekStart: monday, days: plan, today: Fixtures.day("2026-10-21"))
        #expect(board.isEditable(2))
        #expect(board.tap(2) == .selected)
        board.pick(.sport("swim"))
        #expect(board.days[2] == .train(.sport("swim")))
        #expect(board.plannedDays == 6, "one rest day fewer")
    }

    @Test func thisWeekTurnsADayStillToComeIntoASportOrRest() {
        var board = WeekBoard(weekStart: monday, days: plan, today: Fixtures.day("2026-10-22"))
        #expect(board.tap(4) == .selected)
        board.rest()
        #expect(board.days[4] == .rest)
        #expect(board.plannedDays == 4, "a rest day more")
        #expect(board.tap(5) == .selected, "a rest day is selected too")
        board.pick(.sport("yoga"))
        #expect(board.days[5] == .train(.sport("yoga")))
        #expect(board.plannedDays == 5)
        #expect(board.tap(5) == .released)
        #expect(board.focus == .none)
    }

    @Test func nextWeekChangesAnyDayToASportOrRest() {
        var board = WeekBoard(weekStart: monday, days: plan, today: Fixtures.day("2026-10-18"))
        #expect(board.tense == .upcoming)
        #expect(board.tap(0) == .selected)
        board.rest()
        #expect(board.days[0] == .rest)
        #expect(board.tap(2) == .selected)
        board.pick(.sport("swim"))
        #expect(board.days[2] == .train(.sport("swim")))
        #expect(board.tap(2) == .released)
        #expect(board.plannedDays == 5)
    }
}
