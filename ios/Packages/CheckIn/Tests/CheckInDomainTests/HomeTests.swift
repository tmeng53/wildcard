import CheckInDomain
import Contracts
import Foundation
import Testing

private func checkIn(_ number: Int, by member: MemberID, on day: LocalDay = tuesday, _ entry: CheckIn.Entry) throws
    -> CheckIn
{
    CheckIn(
        id: CheckInID(id(number)), member: member, day: day,
        createdAt: Timestamp(millisecondsSince1970: 1_792_500_000_000 + Int64(number)),
        audience: try Audience([squadID]),
        entry: entry)
}

@Test func eachMembersTodayIsTheirLatestTrainingAndTheirDisclaimer() throws {
    let home = sampleHome(checkIns: [
        try checkIn(1, by: mate, on: tuesday.adding(days: -1), .trained(Training(activity: .sport("swim")))),
        try checkIn(2, by: mate, .disclaimer(try Disclaimer("腿还没回来"))),
        try checkIn(3, by: mate, .trained(Training(activity: .sport("yoga")))),
        try checkIn(4, by: mate, .trained(Training(activity: .sport("climb")))),
        try checkIn(5, by: mate, .healthyMeal(Meal())),
    ])
    #expect(home.todaysCheckIns(of: mate).map(\.id) == [2, 3, 4, 5].map { CheckInID(id($0)) })
    #expect(home.todaysSport(of: mate) == .sport("climb"))
    #expect(home.todaysDisclaimer(of: mate) == "腿还没回来")
    #expect(home.todaysSport(of: myID) == nil)
    #expect(home.todaysDisclaimer(of: myID) == nil)
}

@Test func withoutAPlannedSportANewTrainingStartsWithTheLastOne() throws {
    let home = sampleHome(checkIns: [try checkIn(1, by: myID, .trained(Training(activity: .sport("tennis"))))])
    // Monday's plan says train with no sport.
    #expect(home.suggestedActivity(on: tuesday.adding(days: -1)) == .sport("tennis"))
    #expect(home.suggestedActivity(on: tuesday) == .sport("yoga"))
}

@Test func recentSportsAreTheLoggedOnesNewestFirstThenThePlannedOnesWithoutRepeats() throws {
    let home = sampleHome(checkIns: [
        try checkIn(1, by: myID, .trained(Training(activity: .sport("tennis")))),
        try checkIn(2, by: myID, .trained(Training(activity: .sport("swim")))),
        try checkIn(3, by: mate, .trained(Training(activity: .sport("climb")))),
    ])
    let recent = home.recentActivities()
    #expect(Array(recent.prefix(2)) == [.sport("swim"), .sport("tennis")])
    #expect(Set(recent).count == recent.count)
    #expect(!recent.contains(.sport("climb")))
    #expect(home.recentActivities(limit: 1) == [.sport("swim")])
}

@Test func aHomeRolledIntoANewWeekStartsTheWeeksFromNothing() {
    var trained = sampleToday()
    trained.members[1] = entry(myID, .trained, since: 1_792_512_000_000)
    trained.today.trained = 2
    let monday = tuesday.adding(days: 6)

    let rolled = sampleHome(today: trained).rolled(to: monday)
    #expect(rolled.mine?.day == monday)
    #expect(rolled.mine?.training == .notCheckedIn)
    #expect(rolled.mine?.plannedRest == false)
    #expect(rolled.today.today == TodayCounts(trained: 1, disclaimer: 0, resting: 1, everyoneTrained: false))
    #expect(rolled.today.myWeek.firstDay == monday)
    #expect(rolled.today.myWeek.week == WeekCount(trainedDays: 0, plannedDays: 5))
    #expect(rolled.today.myWeek.lifetimeTrainedDays == 30)
    #expect(rolled.today.squadWeek == WeekCount(trainedDays: 0, plannedDays: 22))
    // Already on that day, nothing moves.
    #expect(rolled.rolled(to: monday) == rolled)
}

@Test func aHomeRolledOntoAPlannedRestDayCountsTheMemberResting() {
    // Wednesday rests in the plan.
    let rolled = sampleHome().rolled(to: tuesday.adding(days: 1))
    #expect(rolled.mine?.plannedRest == true)
    #expect(rolled.today.today.resting == 2)
    #expect(rolled.today.squadWeek == WeekCount(trainedDays: 14, plannedDays: 22))
}

@Test func myWeekShowsEachDaysOneStatusWhatITrainedAndMyMeals() throws {
    let monday = tuesday.adding(days: -1)
    let home = sampleHome(checkIns: [
        try checkIn(1, by: myID, on: monday, .trained(Training(activity: .sport("swim")))),
        try checkIn(2, by: myID, on: monday, .trained(Training(activity: .sport("swim")))),
        try checkIn(3, by: myID, on: monday, .healthyMeal(Meal())),
        try checkIn(4, by: myID, .disclaimer(try Disclaimer("腿还没回来"))),
        try checkIn(5, by: myID, .trained(Training(activity: .sport("run")))),
        try checkIn(6, by: myID, .cheatMeal(Meal())),
        try checkIn(9, by: myID, .trained(Training(activity: .sport("swim")))),
        try checkIn(7, by: mate, .trained(Training(activity: .sport("yoga")))),
        // Last week's doesn't count.
        try checkIn(8, by: myID, on: monday.adding(days: -1), .trained(Training(activity: .sport("run")))),
    ])
    let week = home.week(on: tuesday)
    // Wednesday and Sunday are rest days in the plan; a 练了 beats the 请假条 on Tuesday.
    #expect(week.days == [.trained, .trained, .restDay, .open, .open, .open, .restDay])
    #expect(week.today == 1)
    // A day shows what I trained on it (Monday's swim, Tuesday's run over the plan's yoga), else the plan's.
    #expect(week.activities == [.sport("swim"), .sport("run"), nil, nil, nil, nil, nil])
    // Two swims on Monday are one day of swimming.
    #expect(week.trained.map(\.activity) == [.sport("swim"), .sport("run")])
    #expect(week.trained.map(\.days) == [2, 1])
    #expect(week.healthyMeals == 1)
    #expect(week.cheatMeals == 1)

    let onLeave = sampleHome(checkIns: [try checkIn(1, by: myID, .disclaimer(try Disclaimer("加班")))])
    #expect(onLeave.week(on: tuesday).days[1] == .disclaimer)
}

@Test func aCheckInSentOnlyToAnotherSquadDoesntShowOnThisOne() throws {
    let elsewhere = CheckIn(
        id: CheckInID(id(60)), member: myID, day: tuesday,
        createdAt: Timestamp(millisecondsSince1970: 1_792_512_000_000),
        audience: try Audience([SquadID(id(11))]), entry: .trained(Training(activity: .sport("swim"))))
    let home = sampleHome(checkIns: [elsewhere])
    #expect(home.todaysCheckIns(of: myID).isEmpty)
    #expect(home.todaysSport(of: myID) == nil)
}
