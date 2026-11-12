import Contracts
import HealthDomain
import Testing

@testable import CheckInDomain

private func ride(_ id: String) -> ImportedWorkout {
    ImportedWorkout(
        workout: Workout(
            source: WorkoutSource(provider: WorkoutSource.appleHealth, id: id),
            startedAt: Timestamp(millisecondsSince1970: 1_792_513_000_000),
            endedAt: Timestamp(millisecondsSince1970: 1_792_515_000_000), summary: WorkoutSummary(durationSec: 1920)),
        activity: .sport("roadCycling"))
}

private let asked = WorkoutSource(provider: WorkoutSource.appleHealth, id: "ride")

@Test func opensTheAskedWorkoutWhileTheServersHomeHasItUnposted() {
    let todays = [
        TodaysWorkout(imported: ride("run"), isPosted: false), TodaysWorkout(imported: ride("ride"), isPosted: false),
    ]
    #expect(AskedWorkout.resolve(asked, among: todays, finally: false) == .open(ride("ride")))
}

@Test func waitsUntilTheServersHomeIsReadThenOpensTheKinds() {
    // Before the server's home: the phone's copy can't say it is still to post.
    #expect(AskedWorkout.resolve(asked, among: nil, finally: false) == .wait)
    // Offline to the end: the kinds, never the page from the phone's copy.
    #expect(AskedWorkout.resolve(asked, among: nil, finally: true) == .kinds)
}

@Test func aWorkoutPostedSinceOrGoneOpensTheKinds() {
    let posted = [TodaysWorkout(imported: ride("ride"), isPosted: true)]
    // Posted from another phone: Health may still bring it, so wait for its read, then the kinds.
    #expect(AskedWorkout.resolve(asked, among: posted, finally: false) == .wait)
    #expect(AskedWorkout.resolve(asked, among: posted, finally: true) == .kinds)
    #expect(AskedWorkout.resolve(asked, among: [], finally: true) == .kinds)
}
