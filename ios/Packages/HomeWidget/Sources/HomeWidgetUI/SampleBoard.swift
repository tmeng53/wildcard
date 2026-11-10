import CheckInDomain
import Contracts
import Foundation
import HealthDomain
import HomeWidgetDomain

/// The board the widget gallery and a build without a backend show: a squad of four (or up to
/// eight, the rest not checked in yet), two of
/// them trained today, and I trained twice this week but not yet today; with `workout`, a 32
/// minute run Health synced at noon, which the 打卡 capsule offers.
public enum SampleBoard {
    /// - Parameters:
    ///   - workout: with a run Health synced today.
    ///   - posted: that run already posted from the capsule.
    ///   - size: how many in the squad, 4 to 8.
    public static func board(on day: LocalDay, workout: Bool = false, posted: Bool = false, size: Int = 4)
        -> WidgetBoard
    {
        let people = (1...min(max(size, 4), 8)).map {
            MemberID(UUID(uuidString: "00000000-0000-0000-0000-00000000000\($0)") ?? UUID())
        }
        let viewer = people[0]
        let monday = day.weekStart
        func row(_ member: MemberID, _ training: TrainingStatus) -> SquadmateToday {
            SquadmateToday(
                member: member, catchphrase: nil, character: nil, day: day, training: training, latestMeal: nil,
                plannedRest: false, firstCheckInAt: nil)
        }
        let today = SquadToday(
            squad: SquadID(UUID()),
            members: [
                row(people[1], .trained), row(people[2], .trained), row(viewer, .notCheckedIn),
            ] + people[3...].map { row($0, .notCheckedIn) },
            today: TodayCounts(trained: 2, disclaimer: 0, resting: 0, everyoneTrained: false),
            myWeek: MyWeek(
                firstDay: monday, lastDay: monday.adding(days: 6), week: WeekCount(trainedDays: 2, plannedDays: 4)),
            squadWeek: WeekCount(trainedDays: 7, plannedDays: 12))
        let home = Home(
            member: viewer, timeZone: .gmt,
            squad: Squad(id: today.squad, name: "周三不练腿俱乐部", inviteCode: "K7M2QX9P", members: people, captain: viewer),
            today: today, plan: plan(of: viewer, from: monday),
            checkIns: posted ? [checkIn(of: run(on: day), by: viewer, to: today.squad, on: day)] : [])
        return WidgetBoard(home: home, day: day, health: workout || posted ? [run(on: day)] : [])
    }

    /// My 训练 posted from `run`.
    private static func checkIn(of run: ImportedWorkout, by member: MemberID, to squad: SquadID, on day: LocalDay)
        -> CheckIn
    {
        guard let audience = try? Audience([squad]), let activity = run.activity else {
            fatalError("one squad and a listed sport are always a post")
        }
        return CheckIn(
            id: CheckInID(UUID()), member: member, day: day, createdAt: run.workout.endedAt, audience: audience,
            entry: .trained(Training(activity: activity, minutes: run.minutes, workout: run.workout)))
    }

    /// A 32 minute, 5.2 km run ending at noon on `day`, on the sample home's clock (GMT).
    private static func run(on day: LocalDay) -> ImportedWorkout {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let noon =
            calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12)) ?? Date()
        let seconds = 32 * 60
        return ImportedWorkout(
            workout: Workout(
                source: WorkoutSource(provider: WorkoutSource.appleHealth, id: "sample-run"),
                startedAt: Timestamp(noon.addingTimeInterval(-Double(seconds))), endedAt: Timestamp(noon),
                summary: WorkoutSummary(durationSec: seconds, distanceM: 5200)),
            activity: .sport("run"))
    }

    /// Mondays, Wednesdays, Fridays and Saturdays.
    private static func plan(of member: MemberID, from monday: LocalDay) -> WeeklyPlan {
        let days: [PlanDay] = [.train(nil), .rest, .train(nil), .rest, .train(nil), .train(nil), .rest]
        guard let plan = try? WeeklyPlan(member: member, weekStart: monday, days: days) else {
            fatalError("a seven-day plan is always a plan")
        }
        return plan
    }
}
