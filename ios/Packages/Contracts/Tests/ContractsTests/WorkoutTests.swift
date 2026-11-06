import Contracts
import Testing

private let run = Workout(
    source: WorkoutSource(provider: WorkoutSource.appleHealth, id: "A1"),
    startedAt: Timestamp(millisecondsSince1970: 1_000), endedAt: Timestamp(millisecondsSince1970: 1_921_000),
    summary: WorkoutSummary(durationSec: 1920, distanceM: 5200, paceSecPerKm: 369, avgHr: 148),
    route: [RoutePoint(lat: 0, lon: 0), RoutePoint(lat: 0, lon: 0.01)])

@Test func aStripShowsDurationFirstThenWhatItHasInOrder() {
    let swim = WorkoutSummary(durationSec: 2400, distanceM: 1200, avgHr: 139, laps: 24, poolLengthM: 50)
    #expect(swim.cells == [.duration, .laps, .distance, .averageHeartRate])
    #expect(run.summary.cells == [.duration, .distance, .pace, .averageHeartRate])
    #expect(WorkoutSummary(avgHr: 98, effort: 4).cells == [.averageHeartRate, .effort])
}

@Test func postingDropsStruckCellsButNeverTheDuration() {
    let posted = run.posting(struck: [.averageHeartRate, .duration, .pace], tilePosition: 1)
    #expect(posted.summary == WorkoutSummary(durationSec: 1920, distanceM: 5200))
    #expect(posted.route == run.route)
    #expect(posted.tilePosition == 1)
}

@Test func takingTheTileOffKeepsNoRoute() {
    let posted = run.posting(struck: [], tilePosition: nil)
    #expect(posted.route == nil)
    #expect(posted.series == nil)
    #expect(posted.tilePosition == nil)
}

@Test func lapsGoWithTheirPoolLength() {
    let swim = WorkoutSummary(durationSec: 2400, laps: 24, poolLengthM: 50)
    #expect(swim.without([.laps]) == WorkoutSummary(durationSec: 2400))
}

@Test func theRouteLosesTwoHundredMetresAtEachEnd() {
    // About 111 m between points along the equator: 0.001° of longitude.
    let line = (0...20).map { RoutePoint(lat: 0, lon: Double($0) * 0.001) }
    let trimmed = line.trimmed()
    #expect(trimmed.first == line[2])
    #expect(trimmed.last == line[18])
    #expect(Array(line.prefix(4)).trimmed().isEmpty)
}

@Test func thinningKeepsTheEndsAndTheLimit() {
    let line = (0...999).map { RoutePoint(lat: 0, lon: Double($0) * 0.0001) }
    let thinned = line.thinned(to: 100)
    #expect(thinned.count == 100)
    #expect(thinned.first == line.first)
    #expect(thinned.last == line.last)
    let beats = (0..<600).map { HeartRatePoint(seconds: Double($0) * 5, bpm: $0 < 300 ? 100 : 160) }
    let curve = beats.thinned(to: 120)
    #expect(curve.count == 120)
    #expect(curve.first == HeartRatePoint(seconds: 0, bpm: 100))
    #expect(curve.last?.bpm == 160)
}

@Test func theFastestLapIsTheShortest() {
    #expect(WorkoutSeries(laps: [52, 49, 55]).fastestLap == 1)
    #expect(WorkoutSeries(hr: [HeartRatePoint(seconds: 0, bpm: 90)]).isDrawable == false)
}

@Test func theTileSitsAtItsPlaceAmongThePhotos() throws {
    let photo = try PhotoRef(path: "a/b")
    let placed = Workout(
        source: run.source, startedAt: run.startedAt, endedAt: run.endedAt, summary: run.summary, route: run.route,
        tilePosition: 2)
    let training = Training(activity: .sport("run"), photos: try Photos([photo]), workout: placed)
    #expect(training.tiles == [.photo(photo), .workout(.map)])
    #expect(Training(activity: .sport("run"), workout: run).tiles.isEmpty)
}
