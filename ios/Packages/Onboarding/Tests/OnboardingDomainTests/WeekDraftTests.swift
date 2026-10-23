import Contracts
import OnboardingDomain
import Testing

struct WeekDraftTests {
    private let run = PlanDay.train(.sport(.run))
    private let strength = PlanDay.train(.sport(.strength))

    @Test func aWeekStartsAsTheDesignShowsIt() {
        let week = WeekDraft(sports: [.sport(.run), .sport(.strength)], daysGone: 0)
        #expect(week.days == [run, strength, .rest, run, strength, run, .rest])
        #expect(week.trainingDays == 5)
        #expect(week.selected == 0)
        #expect(week.choices == [run, strength, .rest])
    }

    @Test func withNoSportPickedTrainingDaysNameNone() {
        let week = WeekDraft(sports: [], daysGone: 0)
        #expect(week.choices == [.train(nil), .rest])
        #expect(week.days.first == .train(nil))
    }

    @Test func pickingADayMovesOnToTheNext() {
        var week = WeekDraft(sports: [.sport(.run)], daysGone: 0)
        #expect(week.set(.rest) == false)
        #expect(week.selected == 1)
        week.select(2)
        #expect(week.set(run) == true)
        #expect(week.days[2] == run)
        #expect(week.selected == 3)
    }

    @Test func afterTheLastDayItGoesBackToToday() {
        var week = WeekDraft(sports: [.sport(.run)], daysGone: 3)
        week.select(6)
        week.set(run)
        #expect(week.selected == 3)
    }

    @Test func daysAlreadyOverAreRestAndStayShut() {
        var week = WeekDraft(sports: [.sport(.run)], daysGone: 3)
        #expect(week.days == [.rest, .rest, .rest, run, run, run, .rest])
        #expect(week.selected == 3)
        week.select(1)
        #expect(week.selected == 3)
        #expect(!week.isOpen(2))
        #expect(week.isOpen(3))
    }

    @Test func daysGoneIsClampedToTheWeek() {
        #expect(WeekDraft(sports: [], daysGone: -2).daysGone == 0)
        #expect(WeekDraft(sports: [], daysGone: 9).daysGone == 6)
    }

    @Test func thePlanIsTheWeeksDays() throws {
        let week = WeekDraft(sports: [.sport(.run)], daysGone: 0)
        let member = MemberID(.init())
        let plan = try week.plan(for: member, weekStart: try LocalDay("2026-10-19"))
        #expect(plan.days == week.days)
        #expect(plan.weekStart == (try LocalDay("2026-10-19")))
    }
}
