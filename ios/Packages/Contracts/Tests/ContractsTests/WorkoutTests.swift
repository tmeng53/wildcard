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

@Test func postingDropsStruckCellsTheDurationToo() {
    let posted = run.posting(struck: [.averageHeartRate, .duration, .pace], positions: [.map: 1])
    #expect(posted.summary == WorkoutSummary(distanceM: 5200))
    #expect(posted.summary.cells == [.distance])
    #expect(run.posting(struck: Set(WorkoutCell.allCases), positions: [:]).summary.cells.isEmpty)
    #expect(posted.route == run.route)
    #expect(posted.tilePosition == 1)
}

@Test func takingTheTileOffKeepsNoRoute() {
    let posted = run.posting(struck: [], positions: [:])
    #expect(posted.route == nil)
    #expect(posted.series == nil)
    #expect(posted.tilePosition == nil)
}

@Test func strikingWhatTheChartShowsTakesTheChartOff() {
    let beats = [HeartRatePoint(seconds: 0, bpm: 120), HeartRatePoint(seconds: 60, bpm: 150)]
    let yoga = Workout(
        source: WorkoutSource(provider: WorkoutSource.appleHealth, id: "Y1"),
        startedAt: Timestamp(millisecondsSince1970: 0), endedAt: Timestamp(millisecondsSince1970: 60_000),
        summary: WorkoutSummary(durationSec: 60, avgHr: 135, maxHr: 150), series: WorkoutSeries(heartRate: beats))
    #expect(yoga.chartCell == .averageHeartRate)
    #expect(yoga.posting(struck: [.maxHeartRate], positions: [.chart: 1]).series == yoga.series)
    let struck = yoga.posting(struck: [.averageHeartRate], positions: [.chart: 1])
    #expect(struck.series == nil)
    #expect(struck.tilePosition == nil)
    let swim = Workout(
        source: WorkoutSource(provider: WorkoutSource.appleHealth, id: "S1"),
        startedAt: Timestamp(millisecondsSince1970: 0), endedAt: Timestamp(millisecondsSince1970: 60_000),
        summary: WorkoutSummary(durationSec: 60, avgHr: 135, laps: 2, poolLengthM: 50),
        series: WorkoutSeries(heartRate: beats, laps: [30, 30]))
    #expect(swim.chartCell == .laps)
    #expect(swim.posting(struck: [], positions: [.chart: 1]).series == swim.series)
    #expect(swim.posting(struck: [.averageHeartRate], positions: [.chart: 1]).series == WorkoutSeries(laps: [30, 30]))
    #expect(run.chartCell == nil)
}

@Test func aRouteWithHeartRateShowsTheMapAndTheChartEachInItsPlace() throws {
    let beats = [HeartRatePoint(seconds: 0, bpm: 120), HeartRatePoint(seconds: 60, bpm: 150)]
    let both = Workout(
        source: run.source, startedAt: run.startedAt, endedAt: run.endedAt, summary: run.summary,
        series: WorkoutSeries(heartRate: beats), route: run.route)
    #expect(both.tiles == [.map, .chart])
    #expect(both.chartCell == .averageHeartRate)

    // The map keeps `tilePosition`, as builds from before read it; the chart gets its own.
    let posted = both.posting(struck: [], positions: [.chart: 1, .map: 3])
    #expect(posted.tilePosition == 3)
    #expect(posted.chartPosition == 1)
    #expect(posted.position(of: .map) == 3)
    #expect(posted.position(of: .chart) == 1)
    let photos = try Photos([try PhotoRef(path: "m/a"), try PhotoRef(path: "m/b")])
    let training = Training(activity: .sport("run"), minutes: nil, photos: photos, caption: nil, workout: posted)
    #expect(
        training.tiles == [
            .workout(.chart), .photo(try PhotoRef(path: "m/a")), .workout(.map), .photo(try PhotoRef(path: "m/b")),
        ])

    // Striking 平均心率 takes the chart off and leaves the map where it was.
    let mapOnly = both.posting(struck: [.averageHeartRate], positions: [.chart: 1, .map: 2])
    #expect(mapOnly.series == nil)
    #expect(mapOnly.tilePosition == 2)
    #expect(mapOnly.chartPosition == nil)

    // Without the map, the chart takes `tilePosition`.
    let chartOnly = both.posting(struck: [], positions: [.chart: 2])
    #expect(chartOnly.route == nil)
    #expect(chartOnly.tilePosition == 2)
    #expect(chartOnly.chartPosition == nil)
    #expect(chartOnly.position(of: .chart) == 2)
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
    #expect(WorkoutSeries(heartRate: [HeartRatePoint(seconds: 0, bpm: 90)]).isDrawable == false)
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
