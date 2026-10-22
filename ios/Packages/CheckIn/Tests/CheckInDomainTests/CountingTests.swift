import CheckInDomain
import Contracts
import Testing

private func mine(_ entry: CheckIn.Entry, at millis: Int64 = 1_792_515_600_000, day: LocalDay = tuesday) throws
    -> CheckIn
{
    CheckIn(
        id: CheckInID(id(99)), member: myID, day: day, createdAt: Timestamp(millisecondsSince1970: millis),
        audience: try Audience([squadID]), entry: entry)
}

@Test func myFirstCheckInMovesMeUpAfterThoseWhoCheckedInEarlier() throws {
    let counted = sampleToday().countingMine(try mine(.cheatMeal(Meal())))
    #expect(counted.members.map(\.member) == [mate, myID, resting])
    #expect(counted.members[1].latestMeal == .cheatMeal)
    #expect(counted.members[1].firstCheckInAt == Timestamp(millisecondsSince1970: 1_792_515_600_000))
    #expect(counted.today == sampleToday().today)
}

@Test func trainingOnAPlannedRestDayLeavesTheRestersCount() throws {
    var today = sampleToday()
    today.members = [entry(mate, .trained, since: 1), entry(myID, .notCheckedIn, plannedRest: true)]
    today.today = TodayCounts(trained: 1, disclaimer: 0, resting: 1, everyoneTrained: true)
    let counted = today.countingMine(try mine(.trained(Training(activity: .sport(.run)))))
    #expect(counted.today == TodayCounts(trained: 2, disclaimer: 0, resting: 0, everyoneTrained: true))
}

@Test func everyoneTrainedOnceTheLastWhoWasntRestingTrains() throws {
    let counted = sampleToday().countingMine(try mine(.trained(Training(activity: .sport(.run)))))
    #expect(counted.today == TodayCounts(trained: 2, disclaimer: 0, resting: 1, everyoneTrained: true))
    #expect(counted.myWeek.lifetimeTrainedDays == 31)
}

@Test func aCheckInForAnotherDayIsntCountedToday() throws {
    let counted = sampleToday().countingMine(
        try mine(.trained(Training(activity: .sport(.run))), day: tuesday.adding(days: -1)))
    #expect(counted == sampleToday())
}
