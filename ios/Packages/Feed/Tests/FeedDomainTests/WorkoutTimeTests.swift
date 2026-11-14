import Contracts
import Testing

@testable import FeedDomain

private func posted(_ entry: CheckIn.Entry) -> CheckIn {
    let made = checkIn(1, by: coco, on: "2026-10-22", at: 12_600)
    return CheckIn(
        id: made.id, member: made.member, day: made.day, createdAt: made.createdAt, audience: made.audience,
        entry: entry)
}

private let walk = Workout(
    source: WorkoutSource(provider: WorkoutSource.appleHealth, id: "w1"), startedAt: at(1_380), endedAt: at(2_580),
    summary: WorkoutSummary(durationSec: 1_200))

@Test func aTrainingFromHealthShowsWhenTheWorkoutRanNotWhenItWasPosted() throws {
    let training = Training(activity: .sport("walk"), startTime: try StartTime(hour: 7, minute: 0), workout: walk)
    #expect(WorkoutTime(posted(.trained(training))) == .moments(start: at(1_380), end: at(2_580)))
}

@Test func aTrainingPostedByHandShowsTheStartPickedAndItsMinutes() throws {
    let start = try StartTime(hour: 20, minute: 3)
    let timed = Training(activity: .sport("walk"), minutes: try WorkoutMinutes(20), startTime: start)
    #expect(WorkoutTime(posted(.trained(timed))) == .wallClock(start: start, minutes: 20))
    let open = Training(activity: .sport("walk"), startTime: start)
    #expect(WorkoutTime(posted(.trained(open))) == .wallClock(start: start, minutes: nil))
}

@Test func aTrainingWithNoStartAndAnythingElseShowNoWorkoutTime() throws {
    #expect(WorkoutTime(posted(.trained(Training(activity: .sport("walk"))))) == nil)
    #expect(WorkoutTime(posted(.disclaimer(try Disclaimer("腿说今天它请假")))) == nil)
}
