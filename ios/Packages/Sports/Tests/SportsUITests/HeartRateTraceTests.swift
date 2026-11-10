import Contracts
import SportsUI
import Testing

private let zones = HeartRateZones(light: 107, moderate: 119, vigorous: 144, peak: 175)

private let curve = [
    HeartRatePoint(seconds: 0, bpm: 100), HeartRatePoint(seconds: 60, bpm: 110),
    HeartRatePoint(seconds: 120, bpm: 112), HeartRatePoint(seconds: 180, bpm: 150),
    HeartRatePoint(seconds: 300, bpm: 130),
]

@Test func theLineBreaksWhereTheZoneChangesWithoutGaps() {
    let stretches = HeartRateTrace(points: curve, zones: zones).stretches
    #expect(stretches.map(\.zone) == [nil, .light, .vigorous, .moderate])
    #expect(stretches.map { $0.points.map(\.bpm) } == [[100], [100, 110, 112], [112, 150], [150, 130]])
}

@Test func withoutZonesTheLineIsOneStretch() {
    let trace = HeartRateTrace(points: curve, zones: nil)
    #expect(trace.stretches.map(\.zone) == [nil])
    #expect(trace.minutes.isEmpty)
    #expect(trace.bpmRange == 94...156)
}

@Test func aFingerLandsOnTheClosestReading() {
    let trace = HeartRateTrace(points: curve, zones: zones)
    #expect(trace.reading(at: 170)?.bpm == 150)
    #expect(trace.reading(at: -10)?.bpm == 100)
}

@Test func theAxisReachesEveryZoneAndTheMinutesAreWhole() {
    let trace = HeartRateTrace(points: curve, zones: zones)
    #expect(trace.bpmRange == 94...181)
    #expect(trace.minutes.map(\.minutes) == [2, 0, 2, 0])
}

@Test func aZoneStartTooCloseToTheOneBelowIsLeftUnlabelled() {
    let trace = HeartRateTrace(points: curve, zones: zones)
    #expect(trace.labelledStarts(height: 87, labelHeight: 14) == [107, 144, 175])
    #expect(trace.labelledStarts(height: 300, labelHeight: 14) == [107, 119, 144, 175])
    #expect(HeartRateTrace(points: curve, zones: nil).labelledStarts(height: 300, labelHeight: 14).isEmpty)
}
