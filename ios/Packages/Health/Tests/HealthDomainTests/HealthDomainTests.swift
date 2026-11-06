import Contracts
import Foundation
import HealthDomain
import Testing

private let newYork = TimeZone(identifier: "America/New_York")!

private func imported(_ id: String, endingAt moment: String, seconds: Int = 1920) throws -> ImportedWorkout {
    let end = try Timestamp(moment)
    return ImportedWorkout(
        workout: Workout(
            source: WorkoutSource(provider: WorkoutSource.appleHealth, id: id),
            startedAt: Timestamp(millisecondsSince1970: end.millisecondsSince1970 - Int64(seconds) * 1000),
            endedAt: end, summary: WorkoutSummary(durationSec: seconds, avgHr: 140)),
        activity: .sport("run"))
}

@Test func todayIsTheMembersDayNewestFirstWithPostedMarked() throws {
    let morning = try imported("A", endingAt: "2026-11-06T12:10:00Z")
    let evening = try imported("B", endingAt: "2026-11-07T01:40:00Z")
    // 2:30am in New York the next morning still counts for the 6th.
    let late = try imported("C", endingAt: "2026-11-07T07:30:00Z")
    let yesterday = try imported("D", endingAt: "2026-11-05T20:00:00Z")
    let today = [morning, yesterday, late, evening].today(
        try LocalDay("2026-11-06"), in: newYork, posted: [late.id])
    #expect(today.map(\.imported.id.id) == ["C", "B", "A"])
    #expect(today.map(\.isPosted) == [true, false, false])
    #expect(today.newestToPost?.id.id == "B")
}

@Test func minutesRoundAndStayInTheAPIsRange() throws {
    #expect(try imported("A", endingAt: "2026-11-06T12:00:00Z", seconds: 1950).minutes?.value == 33)
    #expect(try imported("A", endingAt: "2026-11-06T12:00:00Z", seconds: 10).minutes?.value == 1)
    #expect(try imported("A", endingAt: "2026-11-06T23:00:00Z", seconds: 40000).minutes?.value == 600)
}

@Test func switchedOffNumbersStartStruck() {
    var sharing = HealthSharing()
    #expect(sharing.struck.isEmpty)
    sharing.pace = false
    sharing.heartRate = false
    #expect(sharing.struck == [.pace, .speed, .averageHeartRate, .maxHeartRate])
}

@Test func tilesFollowTheirSwitches() {
    let source = WorkoutSource(provider: WorkoutSource.appleHealth, id: "A")
    let start = Timestamp(millisecondsSince1970: 0)
    let ride = Workout(
        source: source, startedAt: start, endedAt: start, summary: WorkoutSummary(),
        route: [RoutePoint(lat: 0, lon: 0), RoutePoint(lat: 0, lon: 0.01)])
    let swim = Workout(
        source: source, startedAt: start, endedAt: start, summary: WorkoutSummary(),
        series: WorkoutSeries(laps: [50, 48]))
    var sharing = HealthSharing()
    sharing.route = false
    sharing.heartRate = false
    #expect(sharing.keepsTile(of: ride) == false)
    #expect(sharing.keepsTile(of: swim) == true)
    sharing.laps = false
    #expect(sharing.keepsTile(of: swim) == false)
}
