import CheckInDomain
import Contracts
import Foundation
import Testing

/// A squadmate's 训练 on Tuesday, posted at 10:00 in Los Angeles.
private func training(
    by member: MemberID, _ sport: Sport = "run", start: StartTime? = nil, minutes: Int? = nil,
    naming: [MemberID] = [], day: LocalDay = tuesday, squads: [SquadID] = [squadID]
) throws -> CheckIn {
    CheckIn(
        id: CheckInID(UUID()), member: member, day: day, postedDay: day, createdAt: Timestamp(tuesdayMorning),
        audience: try Audience(squads),
        entry: .trained(
            Training(
                activity: .sport(sport), minutes: try minutes.map(WorkoutMinutes.init), startTime: start,
                trainedWith: try TrainedWith(naming))))
}

@Test func theMatesAreTheSquadWithoutMe() {
    let together = TrainingTogether(home: sampleHome(), on: tuesday, around: nil)
    #expect(together.mates.map(\.member) == [mate, resting])
    #expect(together.hints.isEmpty)
}

@Test func aMateWhoNamedMeComesFirstWhateverTheTime() throws {
    let home = sampleHome(checkIns: [
        try training(by: resting, start: StartTime(hour: 7, minute: 10)),
        try training(by: mate, "swim", start: StartTime(hour: 18, minute: 0), minutes: 45, naming: [myID]),
    ])
    let together = TrainingTogether(home: home, on: tuesday, around: try StartTime(hour: 7, minute: 0))
    #expect(
        together.hints == [
            TrainingTogether.Hint(
                mate: mate, activity: .sport("swim"), minutes: try WorkoutMinutes(45),
                startTime: try StartTime(hour: 18, minute: 0), namedMe: true),
            TrainingTogether.Hint(
                mate: resting, activity: .sport("run"), minutes: nil, startTime: try StartTime(hour: 7, minute: 10),
                namedMe: false),
        ])
}

@Test func onlyTrainingsWithinAnHourOfMineAreOffered() throws {
    let home = sampleHome(checkIns: [
        try training(by: mate, start: StartTime(hour: 8, minute: 1)),
        try training(by: resting, start: StartTime(hour: 6, minute: 0)),
    ])
    let together = TrainingTogether(home: home, on: tuesday, around: try StartTime(hour: 7, minute: 0))
    #expect(together.hints.map(\.mate) == [resting])
}

@Test func withoutAStartEveryMateWhoTrainedThatDayIsOffered() throws {
    let home = sampleHome(checkIns: [
        try training(by: mate, start: StartTime(hour: 8, minute: 0)),
        try training(by: resting, start: StartTime(hour: 20, minute: 0)),
    ])
    #expect(TrainingTogether(home: home, on: tuesday, around: nil).hints.map(\.mate) == [resting, mate])
}

@Test func aTrainingWithoutAStartCountsFromWhenItWasPostedLessItsMinutes() throws {
    // Posted at 10:00 after 60 minutes: it started at 9:00.
    let home = sampleHome(checkIns: [try training(by: mate, minutes: 60)])
    let together = TrainingTogether(home: home, on: tuesday, around: try StartTime(hour: 8, minute: 30))
    #expect(together.hints.map(\.startTime) == [try StartTime(hour: 9, minute: 0)])
}

@Test func otherDaysOtherSquadsMealsAndMyOwnAreNotOffered() throws {
    let elsewhere = SquadID(id(11))
    let home = sampleHome(checkIns: [
        try training(by: mate, day: tuesday.adding(days: -1)),
        try training(by: mate, squads: [elsewhere]),
        try training(by: mate, squads: []),
        try training(by: myID),
        CheckIn(
            id: CheckInID(UUID()), member: resting, day: tuesday, postedDay: tuesday,
            createdAt: Timestamp(tuesdayMorning), audience: try Audience([squadID]), entry: .healthyMeal(Meal())),
    ])
    #expect(TrainingTogether(home: home, on: tuesday, around: nil).hints.isEmpty)
}

@Test func eachMateIsOfferedOnceByTheirLatest() throws {
    let home = sampleHome(checkIns: [
        try training(by: mate, "run", start: StartTime(hour: 7, minute: 0)),
        try training(by: mate, "yoga", start: StartTime(hour: 7, minute: 30)),
    ])
    #expect(TrainingTogether(home: home, on: tuesday, around: nil).hints.map(\.activity) == [.sport("yoga")])
}

@Test func iAlsoPostStartsFromTheTrainingThatNamedMe() throws {
    let named = try training(by: mate, "swim", start: StartTime(hour: 18, minute: 0), minutes: 45, naming: [myID])
    let other = try training(by: resting)
    let home = sampleHome(checkIns: [named, other])
    #expect(
        home.hint(along: named.id)
            == TrainingTogether.Hint(
                mate: mate, activity: .sport("swim"), minutes: try WorkoutMinutes(45),
                startTime: try StartTime(hour: 18, minute: 0), namedMe: true))
    #expect(home.hint(along: other.id) == nil)
    #expect(home.hint(along: CheckInID(UUID())) == nil)
}

@Test func togetherAroundAHealthWorkoutUsesItsStartOnMyClock() throws {
    // 15:00 UTC is 8:00 in Los Angeles; the mate started at 8:30, the other at 11:00.
    let workout = Workout(
        source: WorkoutSource(provider: WorkoutSource.appleHealth, id: "A1"),
        startedAt: Timestamp(millisecondsSince1970: 1_792_508_400_000),
        endedAt: Timestamp(millisecondsSince1970: 1_792_510_200_000), summary: WorkoutSummary(durationSec: 1800))
    let home = sampleHome(checkIns: [
        try training(by: mate, start: StartTime(hour: 8, minute: 30)),
        try training(by: resting, start: StartTime(hour: 11, minute: 0)),
    ])
    let together = home.together(on: nil, workout: workout, startTime: try StartTime(hour: 11, minute: 0))
    #expect(together.hints.map(\.mate) == [mate])
}
