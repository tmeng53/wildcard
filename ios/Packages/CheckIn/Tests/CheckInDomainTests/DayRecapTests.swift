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

private func today(_ mine: TrainingStatus, _ mates: TrainingStatus, _ third: TrainingStatus) -> SquadToday {
    var today = sampleToday()
    today.members = [
        entry(mate, mates), entry(myID, mine), entry(resting, third, plannedRest: true),
    ]
    return today
}

@Test func theRecapNamesWhoWentFirstTheDisclaimerAndTheMealsOnly() throws {
    let home = sampleHome(
        today: today(.trained, .trained, .disclaimer),
        checkIns: [
            try post(1, by: mate, .healthyMeal(Meal())),
            try post(2, by: resting, .disclaimer(try Disclaimer("腰说今天不行"))),
            try post(3, by: myID, .trained(Training(activity: .sport(.run)))),
            try post(4, by: mate, .trained(Training(activity: .sport(.swim)))),
            try post(5, by: myID, .cheatMeal(Meal())),
        ])
    let recap = home.recap
    #expect(recap.showedUp == 3)
    #expect(recap.members == 3)
    #expect(
        recap.highlights == [
            .everyoneShowedUp(members: 3), .firstIn(myID, .sport(.run)), .disclaimer(resting, "腰说今天不行"),
        ])
}

@Test func withoutAFullSquadTheMealsMakeTheThirdLine() throws {
    let home = sampleHome(
        today: today(.notCheckedIn, .trained, .notCheckedIn),
        checkIns: [
            try post(1, by: mate, .trained(Training(activity: .sport(.yoga)))),
            try post(2, by: mate, .healthyMeal(Meal())),
            try post(3, by: myID, .healthyMeal(Meal())),
        ])
    #expect(home.recap.showedUp == 1)
    #expect(home.recap.highlights == [.firstIn(mate, .sport(.yoga)), .meals(healthy: 2, cheat: 0)])
}

@Test func aDayWithoutTrainingIsAQuietDay() throws {
    let home = sampleHome(
        today: today(.notCheckedIn, .disclaimer, .notCheckedIn),
        checkIns: [try post(1, by: mate, .disclaimer(try Disclaimer("加班")))])
    #expect(home.recap.highlights == [.disclaimer(mate, "加班"), .quietDay])
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
