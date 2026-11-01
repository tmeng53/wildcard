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
        let week = WeekDraft(sports: [.sport("run"), .sport("strength")])
        #expect(week.days == [.rest, run, .rest, strength, .rest, .rest, .rest])
        #expect(week.trainingDays == 2)
        #expect(week.selected == 0)
        #expect(week.choices == [run, strength, .rest])
        #expect(
            WeekDraft(sports: [.sport("run")]).days == [.rest, .rest, run, .rest, .rest, .rest, .rest])
        let three = WeekDraft(sports: [.sport("run"), .sport("strength"), .sport("swim")])
        #expect(three.days == [run, .rest, strength, .rest, swim, .rest, .rest])
        let four = WeekDraft(sports: [.sport("run"), .sport("strength"), .sport("swim"), .sport("yoga")])
        #expect(four.days == [run, strength, .rest, swim, yoga, .rest, .rest])
    }

    @Test func fiveSportsOrMoreTrainFiveDaysAsTheDesignShowsIt() {
        let sports: [Activity] = [
            .sport("run"), .sport("strength"), .sport("swim"), .sport("yoga"), .sport("tennis"), .sport("climbing"),
        ]
        let week = WeekDraft(sports: sports)
        #expect(week.days == [run, strength, .rest, swim, yoga, tennis, .rest])
        #expect(week.choices == [run, strength, swim, yoga, tennis, climb, .rest])
    }

    @Test func withNoSportPickedTrainingDaysNameNone() {
        let week = WeekDraft(sports: [])
        #expect(week.choices == [.train(nil), .rest])
        #expect(week.days == [.rest, .rest, .train(nil), .rest, .rest, .rest, .rest])
    }

    @Test func pickingADayMovesOnToTheNext() {
        var week = WeekDraft(sports: [.sport("run")])
        #expect(week.set(.rest) == false)
        #expect(week.selected == 1)
        week.select(3)
        #expect(week.set(run) == true)
        #expect(week.days[3] == run)
        #expect(week.selected == 4)
    }

    @Test func afterSundayItGoesBackToMonday() {
        var week = WeekDraft(sports: [.sport("run")])
        week.select(6)
        week.set(run)
        #expect(week.days[6] == run)
        #expect(week.selected == 0)
    }

    /// A template has no days already over: Monday changes even on a Thursday's sign-up.
    @Test func everyDayCanChange() {
        var week = WeekDraft(sports: [.sport("run"), .sport("swim"), .sport("yoga")])
        week.select(1)
        #expect(week.selected == 1)
        #expect(week.set(swim) == true)
        #expect(week.days == [run, swim, swim, .rest, yoga, .rest, .rest])
        week.select(7)
        #expect(week.selected == 2)
    }

    /// Joining on a Thursday, the week counts Thursday to Sunday of the template.
    @Test func theJoiningWeekCountsFromToday() {
        let week = WeekDraft(sports: [.sport("run"), .sport("swim"), .sport("yoga")])
        #expect(week.days == [run, .rest, swim, .rest, yoga, .rest, .rest])
        #expect(week.trainingDays(from: 0) == 3)
        #expect(week.trainingDays(from: 3) == 1)
        #expect(week.trainingDays(from: 5) == 0)
        #expect(week.trainingDays == 3)
    }

    @Test func thePlanIsTheWeeksDays() throws {
        let week = WeekDraft(sports: [.sport("run")])
        let member = MemberID(.init())
        let plan = try week.plan(for: member, weekStart: try LocalDay("2026-10-19"))
        #expect(plan.days == week.days)
        #expect(plan.weekStart == (try LocalDay("2026-10-19")))
    }
}
