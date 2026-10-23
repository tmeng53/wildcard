import CheckInDomain
import Contracts
import Foundation
import Testing

private func post(_ number: Int, by member: MemberID, _ entry: CheckIn.Entry) throws -> CheckIn {
    CheckIn(
        id: CheckInID(id(number)), member: member, day: tuesday,
        createdAt: Timestamp(millisecondsSince1970: 1_792_500_000_000 + Int64(number)),
        audience: try Audience([squadID]), entry: entry)
}

/// Mate, me, and the third member, whose plan rests today.
private func today(_ mates: TrainingStatus, _ mine: TrainingStatus, _ third: TrainingStatus) -> SquadToday {
    var today = sampleToday()
    today.members = [entry(mate, mates), entry(myID, mine), entry(resting, third, plannedRest: true)]
    return today
}

@Test func theBoxScoreListsTrainingByWhoWentFirstThenDisclaimers() throws {
    let home = sampleHome(
        today: today(.trained, .trained, .disclaimer),
        checkIns: [
            try post(1, by: mate, .healthyMeal(Meal())),
            try post(2, by: resting, .disclaimer(try Disclaimer("腰说今天不行"))),
            try post(3, by: myID, .trained(Training(activity: .sport(.run), minutes: try WorkoutMinutes(30)))),
            try post(4, by: mate, .trained(Training(activity: .sport(.swim)))),
            try post(5, by: myID, .cheatMeal(Meal())),
            try post(6, by: myID, .trained(Training(activity: .sport(.yoga), minutes: try WorkoutMinutes(15)))),
        ])
    let recap = home.recap()
    #expect(recap.showedUp == 3)
    #expect(recap.members == 3)
    #expect(
        recap.rows == [
            .init(member: myID, kind: .trained(.sport(.yoga), minutes: 45, meal: .cheatMeal)),
            .init(member: mate, kind: .trained(.sport(.swim), minutes: nil, meal: .healthyMeal)),
            .init(member: resting, kind: .disclaimer("腰说今天不行")),
        ])
    #expect(recap.healthyMeals == 1)
    #expect(recap.cheatMeals == 1)
}

@Test func whoeverHasntCheckedInHasNoRowAndARestDayHasOne() throws {
    let home = sampleHome(
        today: today(.notCheckedIn, .notCheckedIn, .notCheckedIn),
        checkIns: [try post(1, by: mate, .healthyMeal(Meal()))])
    let recap = home.recap()
    #expect(recap.showedUp == 0)
    #expect(recap.rows == [.init(member: resting, kind: .restDay)])
    #expect(recap.healthyMeals == 1)
}

@Test func myPostsStillWaitingToGoOutHaveTheirRow() throws {
    // Offline after 21:00: the squad's today already counts my 练了 and meal, waiting in the outbox.
    let home = sampleHome(today: today(.notCheckedIn, .trained, .notCheckedIn), checkIns: [])
    let waiting = [
        PendingCheckIn(
            id: CheckInID(id(7)), member: myID, day: tuesday,
            createdAt: Timestamp(millisecondsSince1970: 1_792_500_000_007), audience: try Audience([squadID]),
            draft: .trained(.sport(.run), try WorkoutMinutes(40), PostBody(photos: [], caption: ""))),
        PendingCheckIn(
            id: CheckInID(id(8)), member: myID, day: tuesday,
            createdAt: Timestamp(millisecondsSince1970: 1_792_500_000_008), audience: try Audience([squadID]),
            draft: .healthyMeal(PostBody(photos: [], caption: ""))),
    ]
    let recap = home.recap(pending: waiting)
    #expect(recap.showedUp == 1)
    #expect(
        recap.rows == [
            .init(member: myID, kind: .trained(.sport(.run), minutes: 40, meal: .healthyMeal)),
            .init(member: resting, kind: .restDay),
        ])
    #expect(recap.healthyMeals == 1)
}

@Test func theRecapShowsFromNineInTheEveningUntilTheDayEnds() {
    let home = sampleHome()
    // Tuesday in Los Angeles: 20:59, 21:00, then 02:59 and 03:00 the next morning.
    let nine = Date(timeIntervalSince1970: 1_792_555_200)
    #expect(!home.showsRecap(at: nine.addingTimeInterval(-60)))
    #expect(home.showsRecap(at: nine))
    #expect(home.showsRecap(at: nine.addingTimeInterval(6 * 3600 - 60)))
    #expect(!home.showsRecap(at: nine.addingTimeInterval(6 * 3600)))
}
