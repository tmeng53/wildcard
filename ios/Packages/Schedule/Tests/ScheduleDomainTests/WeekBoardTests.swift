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

    @Test func todaysTrainingDayPicksAnotherSportButStaysATrainingDay() {
        var board = WeekBoard(weekStart: monday, days: plan, today: Fixtures.day("2026-10-22"))
        #expect(board.isEditable(3))
        #expect(board.tap(3) == .selected)
        board.rest()
        #expect(board.days[3] == .train(.sport("strength")))
        board.pick(.sport("swim"))
        #expect(board.days[3] == .train(.sport("swim")))
        #expect(board.plannedDays == 5)
    }

    @Test func aRestTodayBecomesATrainingDay() {
        var board = WeekBoard(weekStart: monday, days: plan, today: Fixtures.day("2026-10-21"))
        #expect(board.isEditable(2))
        #expect(board.tap(2) == .selected, "today is picked, not lifted")
        board.pick(.sport("swim"))
        #expect(board.days[2] == .train(.sport("swim")))
        #expect(board.plannedDays == 6, "one rest day fewer")
    }

    @Test func aLiftedRestDayNeverSwapsWithToday() {
        var board = WeekBoard(weekStart: monday, days: plan, today: Fixtures.day("2026-10-22"))
        board.tap(5)
        #expect(!board.isSwapTarget(3))
        #expect(board.tap(3) == .selected, "today is picked, not swapped")
        #expect(board.days == plan)
    }

    @Test func thisWeekPicksAnotherSportButNeverRest() {
        var board = WeekBoard(weekStart: monday, days: plan, today: Fixtures.day("2026-10-22"))
        board.tap(4)
        #expect(!board.offersRest)
        board.rest()
        #expect(board.days[4] == .train(.sport("run")))
        board.pick(.sport("yoga"))
        #expect(board.days[4] == .train(.sport("yoga")))
        #expect(board.plannedDays == 5)
    }

    @Test func thisWeekSwapsALiftedRestDayWithATrainingDay() {
        var board = WeekBoard(weekStart: monday, days: plan, today: Fixtures.day("2026-10-22"))
        #expect(board.tap(5) == .lifted)
        #expect(board.focus == .lifted(5))
        #expect(board.isSwapTarget(4))
        #expect(board.isSwapTarget(6))
        #expect(!board.isSwapTarget(3), "today is no target")
        #expect(!board.isSwapTarget(5), "a rest day is no target")
        #expect(board.tap(6) == .swapped)
        #expect(board.days[5] == .train(.sport("tennis")))
        #expect(board.days[6] == .rest)
        #expect(board.focus == .none)
        #expect(board.plannedDays == 5, "the number of rest days stays")
    }

    @Test func thisWeekLetsGoOfALiftedDayTappedAgainAndIgnoresLockedDays() {
        var board = WeekBoard(weekStart: monday, days: plan, today: Fixtures.day("2026-10-22"))
        board.tap(5)
        #expect(board.tap(1) == .locked)
        #expect(board.focus == .lifted(5))
        #expect(board.tap(5) == .released)
        #expect(board.focus == .none)
        #expect(board.days == plan)
    }

    @Test func thisWeekLiftsARestDayEvenWithAnotherDaySelected() {
        var board = WeekBoard(weekStart: monday, days: plan, today: Fixtures.day("2026-10-21"))
        board.tap(3)
        #expect(board.tap(5) == .lifted)
        #expect(board.focus == .lifted(5))
    }

    @Test func nextWeekChangesAnyDayToASportOrRest() {
        var board = WeekBoard(weekStart: monday, days: plan, today: Fixtures.day("2026-10-18"))
        #expect(board.tense == .upcoming)
        #expect(board.offersRest)
        #expect(board.tap(0) == .selected)
        board.rest()
        #expect(board.days[0] == .rest)
        #expect(board.tap(2) == .selected, "a rest day is selected, not lifted")
        board.pick(.sport("swim"))
        #expect(board.days[2] == .train(.sport("swim")))
        #expect(board.tap(2) == .released)
        #expect(board.plannedDays == 5)
    }
}
