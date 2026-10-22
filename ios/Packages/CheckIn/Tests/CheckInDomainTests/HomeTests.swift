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
        try checkIn(1, by: mate, on: tuesday.adding(days: -1), .trained(Training(activity: .sport(.swim)))),
        try checkIn(2, by: mate, .disclaimer(try Disclaimer("腿还没回来"))),
        try checkIn(3, by: mate, .trained(Training(activity: .sport(.yoga)))),
        try checkIn(4, by: mate, .trained(Training(activity: .sport(.climb)))),
        try checkIn(5, by: mate, .healthyMeal(Meal())),
    ])
    #expect(home.todaysCheckIns(of: mate).map(\.id) == [2, 3, 4, 5].map { CheckInID(id($0)) })
    #expect(home.todaysSport(of: mate) == .sport(.climb))
    #expect(home.todaysDisclaimer(of: mate) == "腿还没回来")
    #expect(home.todaysSport(of: myID) == nil)
    #expect(home.todaysDisclaimer(of: myID) == nil)
}

@Test func withoutAPlannedSportANewTrainingStartsWithTheLastOne() throws {
    let home = sampleHome(checkIns: [try checkIn(1, by: myID, .trained(Training(activity: .sport(.tennis))))])
    // Monday's plan says train with no sport.
    #expect(home.suggestedActivity(on: tuesday.adding(days: -1)) == .sport(.tennis))
    #expect(home.suggestedActivity(on: tuesday) == .sport(.yoga))
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

@Test func aCheckInSentOnlyToAnotherSquadDoesntShowOnThisOne() throws {
    let elsewhere = CheckIn(
        id: CheckInID(id(60)), member: myID, day: tuesday,
        createdAt: Timestamp(millisecondsSince1970: 1_792_512_000_000),
        audience: try Audience([SquadID(id(11))]), entry: .trained(Training(activity: .sport(.swim))))
    let home = sampleHome(checkIns: [elsewhere])
    #expect(home.todaysCheckIns(of: myID).isEmpty)
    #expect(home.todaysSport(of: myID) == nil)
}
