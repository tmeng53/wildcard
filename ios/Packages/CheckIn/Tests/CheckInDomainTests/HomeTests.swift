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
        try checkIn(
            1, by: myID, on: monday, .trained(Training(activity: .sport("swim"), minutes: try WorkoutMinutes(30)))),
        try checkIn(
            2, by: myID, on: monday, .trained(Training(activity: .sport("swim"), minutes: try WorkoutMinutes(20)))),
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
    // Each day's log: Monday's two swims are one swim of 50 minutes.
    #expect(week.logs[0].sessions.map(\.activity) == [.sport("swim")])
    #expect(week.logs[0].sessions.map(\.minutes) == [50])
    #expect(week.logs[0].healthyMeals == 1)
    #expect(week.logs[1].sessions.map(\.activity) == [.sport("run"), .sport("swim")])
    #expect(week.logs[1].sessions.map(\.minutes) == [nil, nil])
    #expect(week.logs[1].cheatMeals == 1)
    #expect(week.logs[2].sessions.isEmpty)
    #expect(week.logs[2].healthyMeals + week.logs[2].cheatMeals == 0)

    let onLeave = sampleHome(checkIns: [try checkIn(1, by: myID, .disclaimer(try Disclaimer("加班")))])
    #expect(onLeave.week(on: tuesday).days[1] == .disclaimer)
}

@Test func myOwnCheckInNotSharedHereStillShowsOnMyCharacter() throws {
    for squads in [[SquadID(id(11))], []] {
        let elsewhere = CheckIn(
            id: CheckInID(id(60)), member: myID, day: tuesday,
            createdAt: Timestamp(millisecondsSince1970: 1_792_512_000_000),
            audience: try Audience(squads), entry: .trained(Training(activity: .sport("swim"))))
        let home = sampleHome(checkIns: [elsewhere])
        #expect(home.todaysCheckIns(of: myID).map(\.id) == [CheckInID(id(60))])
        #expect(home.todaysSport(of: myID) == .sport("swim"))
        #expect(home.mine?.training == .trained)
        // The server already counted it in my week; the squad never sees it.
        #expect(home.today.myWeek == sampleToday().myWeek)
        #expect(home.today.today == sampleToday().today)
    }
}

@Test func whatSomeoneDoesOnTheHomeIsTheirLatestPostAndItsWords() throws {
    // The meal at 2 was posted at 1_792_500_000_002.
    let justAte = Timestamp(millisecondsSince1970: 1_792_500_000_002)
    let trainedThenAte = sampleHome(checkIns: [
        try checkIn(1, by: mate, .trained(Training(activity: .sport("climb"), caption: try Caption("爬到顶了")))),
        try checkIn(2, by: mate, .cheatMeal(Meal())),
    ])
    #expect(trainedThenAte.todaysMeal(of: mate, at: justAte) == .cheatMeal)
    // The bubble says what the latest post says: this meal has no words.
    #expect(trainedThenAte.todaysCaption(of: mate, at: justAte) == nil)

    let ateThenTrained = sampleHome(checkIns: [
        try checkIn(1, by: mate, .healthyMeal(Meal(caption: try Caption("沙拉")))),
        try checkIn(2, by: mate, .trained(Training(activity: .sport("climb")))),
    ])
    #expect(ateThenTrained.todaysMeal(of: mate, at: justAte) == nil)
    #expect(ateThenTrained.todaysCaption(of: mate, at: justAte) == nil)
    #expect(
        sampleHome(checkIns: [try checkIn(1, by: mate, .healthyMeal(Meal(caption: try Caption("沙拉"))))])
            .todaysCaption(of: mate, at: justAte) == "沙拉")

    let yesterday = sampleHome(checkIns: [
        try checkIn(1, by: mate, on: tuesday.adding(days: -1), .healthyMeal(Meal(caption: try Caption("昨天的"))))
    ])
    #expect(yesterday.todaysMeal(of: mate, at: justAte) == nil)
    #expect(yesterday.todaysCaption(of: mate, at: justAte) == nil)
}

@Test func aMealAfterTrainingLastsAnHourThenTheyTrainAgain() throws {
    let trainedThenAte = sampleHome(checkIns: [
        try checkIn(1, by: mate, .trained(Training(activity: .sport("run"), caption: try Caption("5 公里")))),
        try checkIn(2, by: mate, .healthyMeal(Meal(caption: try Caption("沙拉")))),
    ])
    #expect(trainedThenAte.mealEnds(of: mate) == Timestamp(millisecondsSince1970: 1_792_503_600_002))
    let lastMinute = Timestamp(millisecondsSince1970: 1_792_503_600_001)
    #expect(trainedThenAte.todaysMeal(of: mate, at: lastMinute) == .healthyMeal)
    #expect(trainedThenAte.todaysCaption(of: mate, at: lastMinute) == "沙拉")
    let anHourOn = Timestamp(millisecondsSince1970: 1_792_503_600_002)
    #expect(trainedThenAte.todaysMeal(of: mate, at: anHourOn) == nil)
    #expect(trainedThenAte.todaysCaption(of: mate, at: anHourOn) == "5 公里")
    #expect(trainedThenAte.todaysSport(of: mate) == .sport("run"))

    // Without a 练了 first, the meal lasts all day.
    let onlyAte = sampleHome(checkIns: [try checkIn(1, by: mate, .healthyMeal(Meal()))])
    #expect(onlyAte.mealEnds(of: mate) == nil)
    #expect(onlyAte.todaysMeal(of: mate, at: Timestamp(millisecondsSince1970: 1_792_550_000_000)) == .healthyMeal)
    // Nor does a 练了 after the meal leave one to end.
    let ateThenTrained = sampleHome(checkIns: [
        try checkIn(1, by: mate, .healthyMeal(Meal())),
        try checkIn(2, by: mate, .trained(Training(activity: .sport("run")))),
    ])
    #expect(ateThenTrained.mealEnds(of: mate) == nil)
}
