import Contracts
import Foundation
import HealthDomain
import Testing

private let newYork = TimeZone(identifier: "America/New_York") ?? .gmt

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
    // 11:30pm in New York still counts for the 6th; 12:30am is the 7th.
    let late = try imported("C", endingAt: "2026-11-07T04:30:00Z")
    let yesterday = try imported("D", endingAt: "2026-11-05T20:00:00Z")
    let tomorrow = try imported("E", endingAt: "2026-11-07T05:30:00Z")
    let today = [morning, yesterday, late, tomorrow, evening].today(
        try LocalDay("2026-11-06"), in: newYork, posted: [late.id])
    #expect(today.map(\.imported.id.id) == ["C", "B", "A"])
    #expect(today.map(\.isPosted) == [true, false, false])
    #expect(today.newestToPost()?.id.id == "B")
    // Put away from the home's card, B gives way to the one before it, and then to none.
    #expect(today.newestToPost(skipping: [today[1].imported.id])?.id.id == "A")
    #expect(today.newestToPost(skipping: [today[1].imported.id, today[2].imported.id]) == nil)
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
    #expect(sharing.struck == [.pace, .swimPace, .speed, .topSpeed, .averageHeartRate, .maxHeartRate])
    sharing = HealthSharing()
    sharing.distance = false
    sharing.laps = false
    #expect(sharing.struck == [.distance, .descent, .elevationGain, .laps, .runs])
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
    let beats = [HeartRatePoint(seconds: 0, bpm: 120), HeartRatePoint(seconds: 60, bpm: 150)]
    let run = Workout(
        source: source, startedAt: start, endedAt: start, summary: WorkoutSummary(),
        series: WorkoutSeries(heartRate: beats), route: ride.route)
    var sharing = HealthSharing()
    #expect(sharing.keptTiles(of: run) == [.map, .chart])
    sharing.heartRate = false
    #expect(sharing.keptTiles(of: run) == [.map])
    sharing.route = false
    #expect(sharing.keptTiles(of: ride) == [])
    #expect(sharing.keptTiles(of: swim) == [.chart])
    sharing.laps = false
    #expect(sharing.keptTiles(of: swim) == [])
}

@Test func caloriesStayOnForSettingsKeptBeforeThem() throws {
    let kept = Data(
        #"{"version":1,"distance":true,"pace":false,"heartRate":true,"effort":true,"laps":true,"route":true}"#.utf8)
    let sharing = try JSONDecoder().decode(HealthSharing.self, from: kept)
    #expect(sharing.calories)
    #expect(!sharing.pace)
    var off = sharing
    off.calories = false
    #expect(off.struck.contains(.calories))
    #expect(try JSONDecoder().decode(HealthSharing.self, from: JSONEncoder().encode(off)) == off)
}

@Test func zonesArePlacedFromTheBirthdayAndRestingRateOnly() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
    let curve = [HeartRatePoint(seconds: 0, bpm: 100), HeartRatePoint(seconds: 60, bpm: 150)]
    // 2026-11-08 12:00 UTC.
    let workout = Workout(
        source: WorkoutSource(provider: WorkoutSource.appleHealth, id: "HR"),
        startedAt: Timestamp(millisecondsSince1970: 1_794_139_200_000),
        endedAt: Timestamp(millisecondsSince1970: 1_794_139_260_000), summary: WorkoutSummary(avgHr: 125),
        series: WorkoutSeries(heartRate: curve), tilePosition: 1)
    let imported = ImportedWorkout(workout: workout, activity: nil, restingBpm: 60)
    let zoned = imported.withZones(birthday: DateComponents(year: 1992, month: 3, day: 1), calendar: calendar)
    #expect(zoned.series?.zones == HeartRateZones(age: 34, restingBpm: 60))
    #expect(zoned.series?.heartRate == curve)
    #expect(zoned.tilePosition == 1)
    #expect(imported.withZones(birthday: nil, calendar: calendar) == workout)
}
