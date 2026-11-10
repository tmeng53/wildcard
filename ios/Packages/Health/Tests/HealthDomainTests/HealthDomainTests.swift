import Contracts
import Foundation
import HealthDomain
import Testing

private let newYork = TimeZone(identifier: "America/New_York") ?? .gmt

private func imported(
    _ id: String, endingAt moment: String, seconds: Int = 1920, sport: Sport = "run"
) throws -> ImportedWorkout {
    let end = try Timestamp(moment)
    return ImportedWorkout(
        workout: Workout(
            source: WorkoutSource(provider: WorkoutSource.appleHealth, id: id),
            startedAt: Timestamp(millisecondsSince1970: end.millisecondsSince1970 - Int64(seconds) * 1000),
            endedAt: end, summary: WorkoutSummary(durationSec: seconds, avgHr: 140)),
        activity: .sport(sport))
}

/// A 训练 posted from this Health workout.
private func posted(_ imported: ImportedWorkout, on day: String) throws -> PostedTraining {
    PostedTraining(
        activity: try #require(imported.activity), day: try LocalDay(day), madeAt: imported.workout.endedAt,
        workout: imported.workout)
}

/// A 训练 posted by hand, with no workout.
private func byHand(_ sport: Sport, on day: String, at moment: String) throws -> PostedTraining {
    PostedTraining(activity: .sport(sport), day: try LocalDay(day), madeAt: try Timestamp(moment), workout: nil)
}

@Test func todayIsTheMembersDayNewestFirstWithPostedMarked() throws {
    let morning = try imported("A", endingAt: "2026-11-06T12:10:00Z")
    let evening = try imported("B", endingAt: "2026-11-07T01:40:00Z")
    // 11:30pm in New York still counts for the 6th; 12:30am is the 7th.
    let late = try imported("C", endingAt: "2026-11-07T04:30:00Z")
    let yesterday = try imported("D", endingAt: "2026-11-05T20:00:00Z")
    let tomorrow = try imported("E", endingAt: "2026-11-07T05:30:00Z")
    let today = [morning, yesterday, late, tomorrow, evening].today(
        try LocalDay("2026-11-06"), in: newYork, posted: [try posted(late, on: "2026-11-06")])
    #expect(today.map(\.imported.id.id) == ["C", "B", "A"])
    #expect(today.map(\.isPosted) == [true, false, false])
    #expect(today.newestToPost()?.id.id == "B")
    // Put away from the home's card, B gives way to the one before it, and then to none.
    #expect(today.newestToPost(skipping: [today[1].imported.id])?.id.id == "A")
    #expect(today.newestToPost(skipping: [today[1].imported.id, today[2].imported.id]) == nil)
}

@Test func anotherRecordOfAPostedSessionIsPostedToo() throws {
    // The watch and another app both saved the 6:19–6:49pm game; the member posted the watch's.
    let watch = try imported("W", endingAt: "2026-11-09T23:49:04Z", seconds: 1800, sport: "pickleball")
    let app = try imported("A", endingAt: "2026-11-09T23:50:00Z", seconds: 1860, sport: "pickleball")
    // A later game, and a run at the same time, are not the same session.
    let later = try imported("L", endingAt: "2026-11-10T01:30:00Z", seconds: 1800, sport: "pickleball")
    let run = try imported("R", endingAt: "2026-11-09T23:45:00Z", seconds: 1200, sport: "run")
    let today = [watch, app, later, run].today(
        try LocalDay("2026-11-09"), in: newYork, posted: [try posted(watch, on: "2026-11-09")])
    #expect(today.map(\.imported.id.id) == ["L", "A", "W", "R"])
    #expect(today.map(\.isPosted) == [false, true, true, false])
    #expect(today.newestToPost(skipping: [later.id])?.id.id == "R")
}

@Test func aSessionPostedUnderAnIDHealthNoLongerHasIsPosted() throws {
    // The game was posted from Health as "OLD"; Health now keeps the same 6:19–6:49pm game as
    // "NEW" only, and nothing else of it.
    let old = try imported("OLD", endingAt: "2026-11-09T23:49:04Z", seconds: 1800, sport: "pickleball")
    let new = try imported("NEW", endingAt: "2026-11-09T23:49:04Z", seconds: 1800, sport: "pickleball")
    let day = try LocalDay("2026-11-09")
    let today = [new].today(day, in: newYork, posted: [try posted(old, on: "2026-11-09")])
    #expect(today.map(\.isPosted) == [true])
    #expect(today.newestToPost() == nil)
    // A post of another sport at that time, or of the sport earlier that day, covers nothing.
    let run = try imported("RUN", endingAt: "2026-11-09T23:49:04Z", seconds: 1800, sport: "run")
    #expect([new].today(day, in: newYork, posted: [try posted(run, on: "2026-11-09")]).map(\.isPosted) == [false])
    let morning = try imported("AM", endingAt: "2026-11-09T14:00:00Z", seconds: 1800, sport: "pickleball")
    #expect(
        [new].today(day, in: newYork, posted: [try posted(morning, on: "2026-11-09")]).map(\.isPosted) == [false])
}

@Test func aTrainingPostedByHandCoversTheWorkoutOfItsSport() throws {
    // Pickleball 6:00–6:30pm in New York, posted by hand at 7:12pm; a run later that night.
    let pickleball = try imported("P", endingAt: "2026-11-09T23:30:00Z", seconds: 1800, sport: "pickleball")
    let run = try imported("R", endingAt: "2026-11-10T02:00:00Z", sport: "run")
    let day = try LocalDay("2026-11-09")
    let hand = try byHand("pickleball", on: "2026-11-09", at: "2026-11-10T00:12:00Z")
    let today = [pickleball, run].today(day, in: newYork, posted: [hand])
    #expect(today.map(\.imported.id.id) == ["R", "P"])
    #expect(today.map(\.isPosted) == [false, true])
    #expect(today.newestToPost(skipping: [run.id]) == nil)
    // A post of another sport, one made before the workout started, or one of another day,
    // covers nothing.
    let other = try byHand("run", on: "2026-11-09", at: "2026-11-10T00:12:00Z")
    #expect([pickleball, run].today(day, in: newYork, posted: [other]).map(\.isPosted) == [false, false])
    let early = try byHand("pickleball", on: "2026-11-09", at: "2026-11-09T20:00:00Z")
    #expect([pickleball].today(day, in: newYork, posted: [early]).map(\.isPosted) == [false])
    let backfill = try byHand("pickleball", on: "2026-11-08", at: "2026-11-10T00:12:00Z")
    #expect([pickleball].today(day, in: newYork, posted: [backfill]).map(\.isPosted) == [false])
    // Each post covers one workout, the earliest: a second game still waits.
    let second = try imported("P2", endingAt: "2026-11-10T01:00:00Z", seconds: 1800, sport: "pickleball")
    let late = try byHand("pickleball", on: "2026-11-09", at: "2026-11-10T01:30:00Z")
    #expect([pickleball, second].today(day, in: newYork, posted: [late]).map(\.isPosted) == [false, true])
    let both = [pickleball, second].today(day, in: newYork, posted: [try posted(pickleball, on: "2026-11-09"), late])
    #expect(both.map(\.isPosted) == [true, true])
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
    let utc = try #require(TimeZone(identifier: "UTC"))
    let curve = [HeartRatePoint(seconds: 0, bpm: 100), HeartRatePoint(seconds: 60, bpm: 150)]
    // 2026-11-08 12:00 UTC.
    let workout = Workout(
        source: WorkoutSource(provider: WorkoutSource.appleHealth, id: "HR"),
        startedAt: Timestamp(millisecondsSince1970: 1_794_139_200_000),
        endedAt: Timestamp(millisecondsSince1970: 1_794_139_260_000), summary: WorkoutSummary(avgHr: 125),
        series: WorkoutSeries(heartRate: curve), tilePosition: 1)
    let imported = ImportedWorkout(workout: workout, activity: nil, restingBpm: 60)
    let born = Birthday(sent: try LocalDay("1992-03-01"))
    let zoned = imported.withZones(birthday: born, in: utc)
    #expect(zoned.workout.series?.zones == HeartRateZones(age: 34, restingBpm: 60))
    #expect(zoned.workout.series?.heartRate == curve)
    #expect(zoned.workout.tilePosition == 1)
    #expect(zoned.restingBpm == 60)
    // The day before their birthday they are still a year younger.
    let tomorrow = Birthday(sent: try LocalDay("1992-11-09"))
    #expect(
        imported.withZones(birthday: tomorrow, in: utc).workout.series?.zones
            == HeartRateZones(age: 33, restingBpm: 60))
    #expect(imported.withZones(birthday: nil, in: utc) == imported)
    // Without resting heart rate, the zones come from the highest rate alone.
    let unrested = ImportedWorkout(workout: workout, activity: nil)
    #expect(
        unrested.withZones(birthday: born, in: utc).workout.series?.zones == HeartRateZones(age: 34, restingBpm: nil))
}
