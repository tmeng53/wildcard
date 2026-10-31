import Contracts
import OnboardingDomain
import Testing

struct WeekDraftTests {
    private let run = PlanDay.train(.sport("run"))
    private let strength = PlanDay.train(.sport("strength"))

    private let swim = PlanDay.train(.sport("swim"))
    private let yoga = PlanDay.train(.sport("yoga"))
    private let tennis = PlanDay.train(.sport("tennis"))
    private let climb = PlanDay.train(.sport("climbing"))

    @Test func aWeekTrainsOnceForEachSportPicked() {
        let week = WeekDraft(sports: [.sport("run"), .sport("strength")], daysGone: 0)
        #expect(week.days == [.rest, run, .rest, strength, .rest, .rest, .rest])
        #expect(week.trainingDays == 2)
        #expect(week.selected == 0)
        #expect(week.choices == [run, strength, .rest])
        #expect(
            WeekDraft(sports: [.sport("run")], daysGone: 0).days == [.rest, .rest, run, .rest, .rest, .rest, .rest])
        let three = WeekDraft(sports: [.sport("run"), .sport("strength"), .sport("swim")], daysGone: 0)
        #expect(three.days == [run, .rest, strength, .rest, swim, .rest, .rest])
        let four = WeekDraft(sports: [.sport("run"), .sport("strength"), .sport("swim"), .sport("yoga")], daysGone: 0)
        #expect(four.days == [run, strength, .rest, swim, yoga, .rest, .rest])
    }

    @Test func fiveSportsOrMoreTrainFiveDaysAsTheDesignShowsIt() {
        let sports: [Activity] = [
            .sport("run"), .sport("strength"), .sport("swim"), .sport("yoga"), .sport("tennis"), .sport("climbing"),
        ]
        let week = WeekDraft(sports: sports, daysGone: 0)
        #expect(week.days == [run, strength, .rest, swim, yoga, tennis, .rest])
        #expect(week.choices == [run, strength, swim, yoga, tennis, climb, .rest])
    }

    @Test func withNoSportPickedTrainingDaysNameNone() {
        let week = WeekDraft(sports: [], daysGone: 0)
        #expect(week.choices == [.train(nil), .rest])
        #expect(week.days == [.rest, .rest, .train(nil), .rest, .rest, .rest, .rest])
    }

    @Test func pickingADayMovesOnToTheNext() {
        var week = WeekDraft(sports: [.sport("run")], daysGone: 0)
        #expect(week.set(.rest) == false)
        #expect(week.selected == 1)
        week.select(3)
        #expect(week.set(run) == true)
        #expect(week.days[3] == run)
        #expect(week.selected == 4)
    }

    @Test func afterTheLastDayItGoesBackToToday() {
        var week = WeekDraft(sports: [.sport("run")], daysGone: 3)
        week.select(6)
        week.set(run)
        #expect(week.selected == 3)
    }

    @Test func daysAlreadyOverKeepTheTypicalWeekAndStayShut() {
        var week = WeekDraft(sports: [.sport("run"), .sport("swim"), .sport("yoga")], daysGone: 3)
        #expect(week.days == [run, .rest, swim, .rest, yoga, .rest, .rest])
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
        let week = WeekDraft(sports: [.sport("run")], daysGone: 0)
        let member = MemberID(.init())
        let plan = try week.plan(for: member, weekStart: try LocalDay("2026-10-19"))
        #expect(plan.days == week.days)
        #expect(plan.weekStart == (try LocalDay("2026-10-19")))
    }
}
