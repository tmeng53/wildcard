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
