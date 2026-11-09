import Contracts
import Foundation
import Testing

@Test func zonesStartAtSharesOfTheHeartRateReserve() throws {
    // Age 34: highest 208 − 23.8 = 184.2; resting 60, so the reserve is 124.2.
    let zones = try #require(HeartRateZones(age: 34, restingBpm: 60))
    #expect(zones.starts == [97, 110, 135, 166])
}

@Test func withoutARestingRateZonesAreSharesOfTheHighest() throws {
    let zones = try #require(HeartRateZones(age: 34, restingBpm: nil))
    #expect(zones.starts == [105, 118, 142, 166])
}

@Test func anAgeOrRestingRateOutOfRangeGivesNoZones() {
    #expect(HeartRateZones(age: 9, restingBpm: 60) == nil)
    #expect(HeartRateZones(age: 34, restingBpm: 150) == nil)
    #expect(HeartRateZones(light: 120, moderate: 110, vigorous: 140, peak: 170) == nil)
}

@Test func aReadingFallsInTheHighestZoneItReaches() throws {
    let zones = try #require(HeartRateZones(light: 107, moderate: 119, vigorous: 144, peak: 175))
    #expect(zones.zone(of: 100) == nil)
    #expect(zones.zone(of: 107) == .light)
    #expect(zones.zone(of: 143) == .moderate)
    #expect(zones.zone(of: 182) == .peak)
}

@Test func eachReadingCountsUntilTheNextOne() throws {
    let zones = try #require(HeartRateZones(light: 107, moderate: 119, vigorous: 144, peak: 175))
    let points = [
        HeartRatePoint(seconds: 0, bpm: 100), HeartRatePoint(seconds: 60, bpm: 110),
        HeartRatePoint(seconds: 180, bpm: 150), HeartRatePoint(seconds: 200, bpm: 112),
        HeartRatePoint(seconds: 260, bpm: 90),
    ]
    #expect(zones.seconds(in: points) == [.light: 180, .vigorous: 20])
}

@Test func zonesThatDoNotRiseAreRefusedWhenRead() {
    let json = Data(#"{"light":120,"moderate":110,"vigorous":140,"peak":170}"#.utf8)
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(HeartRateZones.self, from: json) }
}

@Test func aSeriesWithoutHeartRateKeepsNoZones() throws {
    let zones = try #require(HeartRateZones(light: 107, moderate: 119, vigorous: 144, peak: 175))
    #expect(WorkoutSeries(laps: [50, 52], zones: zones).zones == nil)
}
