import CheckInDomain
import Contracts
import Foundation
import HomeWidgetDomain

/// The board the widget gallery and a build without a backend show: a squad of four, two of
/// them trained today, and I trained twice this week but not yet today.
public enum SampleBoard {
    public static func board(on day: LocalDay) -> WidgetBoard {
        let people = (1...4).map { MemberID(UUID(uuidString: "00000000-0000-0000-0000-00000000000\($0)") ?? UUID()) }
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
                row(people[3], .notCheckedIn),
            ],
            today: TodayCounts(trained: 2, disclaimer: 0, resting: 0, everyoneTrained: false),
            myWeek: MyWeek(
                firstDay: monday, lastDay: monday.adding(days: 6), week: WeekCount(trainedDays: 2, plannedDays: 4)),
            squadWeek: WeekCount(trainedDays: 7, plannedDays: 12))
        let home = Home(
            member: viewer, timeZone: .gmt,
            squad: Squad(id: today.squad, name: "周三不练腿俱乐部", inviteCode: "K7M2QX9P", members: people, captain: viewer),
            today: today, plan: plan(of: viewer, from: monday), checkIns: [])
        return WidgetBoard(home: home, day: day)
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
