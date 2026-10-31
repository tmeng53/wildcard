import CheckInDomain
import Contracts
import Testing

private func mine(
    _ entry: CheckIn.Entry, at millis: Int64 = 1_792_515_600_000, day: LocalDay = tuesday,
    sharedTo squads: [SquadID] = [squadID]
) throws -> CheckIn {
    CheckIn(
        id: CheckInID(id(99)), member: myID, day: day, createdAt: Timestamp(millisecondsSince1970: millis),
        audience: try Audience(squads), entry: entry)
}

@Test func aTrainingSharedToNoSquadCountsInMyRowAndWeekButNotTheSquads() throws {
    let counted = sampleToday().countingMine(try mine(.trained(Training(activity: .sport("run"))), sharedTo: []))
    #expect(counted.members.map(\.member) == [mate, myID, resting])
    #expect(counted.members[1].training == .trained)
    #expect(counted.myWeek.week == WeekCount(trainedDays: 2, plannedDays: 5))
    #expect(counted.today == TodayCounts(trained: 1, disclaimer: 0, resting: 1, everyoneTrained: false))
    #expect(counted.squadWeek == WeekCount(trainedDays: 14, plannedDays: 22))
}

@Test func aDisclaimerSharedElsewhereShowsInMyRowOnly() throws {
    let counted = sampleToday().countingMine(
        try mine(.disclaimer(try Disclaimer("加班")), sharedTo: [SquadID(id(11))]))
    #expect(counted.members[1].training == .disclaimer)
    #expect(counted.today == sampleToday().today)
}

@Test func showingMineChangesMyRowButNoCount() throws {
    let shown = sampleToday().showingMine(try mine(.trained(Training(activity: .sport("run"))), sharedTo: []))
    #expect(shown.members[1].training == .trained)
    #expect(shown.myWeek == sampleToday().myWeek)
    #expect(shown.today == sampleToday().today)
    #expect(shown.squadWeek == sampleToday().squadWeek)
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
    let counted = today.countingMine(try mine(.trained(Training(activity: .sport("run")))))
    #expect(counted.today == TodayCounts(trained: 2, disclaimer: 0, resting: 0, everyoneTrained: true))
}

@Test func everyoneTrainedOnceTheLastWhoWasntRestingTrains() throws {
    let counted = sampleToday().countingMine(try mine(.trained(Training(activity: .sport("run")))))
    #expect(counted.today == TodayCounts(trained: 2, disclaimer: 0, resting: 1, everyoneTrained: true))
}

@Test func aCheckInForAnotherDayIsntCountedToday() throws {
    let counted = sampleToday().countingMine(
        try mine(.trained(Training(activity: .sport("run"))), day: tuesday.adding(days: -1)))
    #expect(counted == sampleToday())
}
