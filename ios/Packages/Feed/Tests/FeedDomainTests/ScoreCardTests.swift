import Contracts
import Foundation
import Testing

@testable import FeedDomain

private func photo(_ path: String) -> PhotoRef {
    do { return try PhotoRef(path: path) } catch { fatalError("bad test photo \(path)") }
}

private let source = WorkoutSource(provider: WorkoutSource.appleHealth, id: "w1")
private let morning = [RoutePoint(lat: 40.78, lon: -73.96), RoutePoint(lat: 40.79, lon: -73.95)]
private let heart = WorkoutSeries(heartRate: [
    HeartRatePoint(seconds: 0, bpm: 120), HeartRatePoint(seconds: 60, bpm: 150),
])

/// A run from Health: 45 minutes, 7.4 km, 6′05″, 151 bpm, 412 kcal.
private func run(photos: [String] = ["a", "b"], route: Bool = true, chart: Bool = true) -> Training {
    let summary = WorkoutSummary(
        durationSec: 2700, distanceM: 7400, paceSecPerKm: 365, avgHr: 151, activeEnergyKcal: 412)
    let workout = Workout(
        source: source, startedAt: at(0), endedAt: at(2700), summary: summary, series: chart ? heart : nil,
        route: route ? morning : nil, tilePosition: 2, chartPosition: 3)
    return Training(
        activity: .sport("run"), photos: photos.isEmpty ? nil : try? Photos(photos.map(photo)), workout: workout)
}

@Test func aRunStandsItsDistanceBigWithTheNextThreeUnder() {
    let card = ScoreCard(training: run(), hasKit: true, holdsProp: false)
    #expect(card.numbers == [.duration, .distance, .pace, .averageHeartRate, .calories])
    #expect(card.hero == .distance)
    #expect(card.strip == [.duration, .pace, .averageHeartRate])
}

@Test func theBackdropsAreThePhotosTheRouteTheChartThenPlainAndTheFirstPhotoComesFirst() {
    let card = ScoreCard(training: run(), hasKit: true, holdsProp: false)
    #expect(card.backdrops == [.photo(photo("a")), .photo(photo("b")), .map, .chart, .plain])
    #expect(card.backdrop == .photo(photo("a")))
    #expect(!card.isPlain)
}

@Test func withoutPhotosTheRouteIsTheBackdropAndWithoutAnyPictureItIsPlain() {
    #expect(ScoreCard(training: run(photos: []), hasKit: true, holdsProp: false).backdrop == .map)
    #expect(ScoreCard(training: run(photos: [], route: false), hasKit: true, holdsProp: false).backdrop == .chart)
    let bare = ScoreCard(training: run(photos: [], route: false, chart: false), hasKit: true, holdsProp: false)
    #expect(bare.backdrops == [.plain])
    #expect(bare.isPlain)
}

@Test func tappingTheBigNumberGoesThroughTheNumbersAndRoundAgain() {
    var card = ScoreCard(training: run(), hasKit: true, holdsProp: false)
    card.nextHero()
    #expect(card.hero == .pace)
    #expect(card.strip == [.duration, .distance, .averageHeartRate])
    card.nextHero()
    card.nextHero()
    card.nextHero()
    #expect(card.hero == .duration)
    card.nextHero()
    #expect(card.hero == .distance)
}

@Test func aStruckNumberIsLeftOutOfTheSavedStripAndATapBringsItBack() {
    var card = ScoreCard(training: run(), hasKit: true, holdsProp: false)
    card.toggle(.pace)
    #expect(card.strip == [.duration, .pace, .averageHeartRate])
    #expect(card.savedStrip == [.duration, .averageHeartRate])
    card.toggle(.pace)
    #expect(card.savedStrip == [.duration, .pace, .averageHeartRate])
    // The big number and a number past the strip's three can't be struck.
    card.toggle(.distance)
    card.toggle(.calories)
    #expect(card.struck.isEmpty)
}

@Test func aStruckNumberTakenUpBigShowsAgain() {
    var card = ScoreCard(training: run(), hasKit: true, holdsProp: false)
    card.toggle(.duration)
    for _ in 0..<4 { card.nextHero() }
    #expect(card.hero == .duration)
    #expect(card.struck.isEmpty)
}

@Test func strengthStandsItsMinutesBigAndAHandMadePostItsMinutesAlone() throws {
    let strength = Training(
        activity: .sport("strength"),
        workout: Workout(
            source: source, startedAt: at(0), endedAt: at(3600),
            summary: WorkoutSummary(durationSec: 3600, avgHr: 128, activeEnergyKcal: 420)))
    let card = ScoreCard(training: strength, hasKit: true, holdsProp: false)
    #expect(card.hero == .duration)
    #expect(card.strip == [.averageHeartRate, .calories])
    let byHand = ScoreCard(
        training: Training(activity: .sport("tennis"), minutes: try WorkoutMinutes(50)), hasKit: true,
        holdsProp: false)
    #expect(byHand.hero == .duration)
    #expect(byHand.strip.isEmpty)
    let noNumbers = ScoreCard(training: Training(activity: .sport("tennis")), hasKit: true, holdsProp: false)
    #expect(noNumbers.hero == nil)
    #expect(noNumbers.strip.isEmpty)
}

@Test func aSkiDayStandsItsDescentBig() {
    let ski = Training(
        activity: .sport("ski"),
        workout: Workout(
            source: source, startedAt: at(0), endedAt: at(9000),
            summary: WorkoutSummary(durationSec: 9000, distanceM: 21000, runs: 12, descentM: 3400, topSpeedKmh: 58)))
    #expect(ScoreCard(training: ski, hasKit: true, holdsProp: false).hero == .descent)
}

@Test func tappingTheCharacterGoesThroughItsPosesWithThePropOnlyWhenItHoldsOne() {
    var card = ScoreCard(training: run(), hasKit: true, holdsProp: true)
    #expect(card.poses == [.sport, .cheer, .flex, .prop])
    #expect(card.pose == .sport)
    card.nextPose()
    card.nextPose()
    card.nextPose()
    #expect(card.pose == .prop)
    card.nextPose()
    #expect(card.pose == .sport)
    let noKit = ScoreCard(training: run(), hasKit: false, holdsProp: false)
    #expect(noKit.poses == [.cheer, .flex])
    #expect(noKit.pose == .cheer)
}

@Test func pickingABackdropTakesOnlyOneThePostHas() {
    var card = ScoreCard(training: run(route: false), hasKit: true, holdsProp: false)
    card.pick(.map)
    #expect(card.backdrop == .photo(photo("a")))
    card.pick(.plain)
    #expect(card.isPlain)
}

@Test func theWeekCountIsWhichOfTheMembersTrainingsThatWeekItIs() {
    // Monday 2026-10-19 to Sunday 2026-10-25.
    let earlier = checkIn(1, by: jay, on: "2026-10-19", at: 10)
    let sameDayFirst = checkIn(2, by: jay, on: "2026-10-21", at: 10)
    let mine = checkIn(3, by: jay, on: "2026-10-21", at: 20)
    let slip = checkIn(4, by: jay, on: "2026-10-20", disclaimer: true)
    let teammate = checkIn(5, by: mia, on: "2026-10-19")
    let lastWeek = checkIn(6, by: jay, on: "2026-10-18")
    let all = [mine, teammate, slip, sameDayFirst, lastWeek, earlier]
    #expect(ScoreCard.weekCount(of: mine, among: all) == 3)
    #expect(ScoreCard.weekCount(of: earlier, among: all) == 1)
    #expect(ScoreCard.weekCount(of: mine, among: [earlier]) == nil)
}

@MainActor @Test func theStoreCountsTheWeekFromTheSquadsPostsAndTheBackfillDaysAfter() async {
    let mine = checkIn(3, by: coco, on: "2026-10-22", at: 20)
    let source = FakeSource([
        FeedPost(checkIn: checkIn(1, by: coco, on: "2026-10-19")), FeedPost(checkIn: mine),
        FeedPost(checkIn: checkIn(2, by: jay, on: "2026-10-20")),
    ])
    let feed = store(source)
    #expect(await feed.weekCount(of: mine) == 2)
    #expect(await source.calls == [.posts(day("2026-10-19"), day("2026-11-01"))])
    await source.fail(with: .notSent)
    #expect(await feed.weekCount(of: mine) == nil)
}
