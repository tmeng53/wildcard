import Contracts
import HealthDomain
import Testing

/// Readings every 10 seconds through `heights`, each leg walked in even steps of `step` metres,
/// at `speed` m/s going down and 4 m/s on the way up.
private func day(_ heights: [Double], step: Double = 10, speed: Double? = 12) -> [SlopeDay.Sample] {
    var altitudes = [heights[0]]
    for (from, next) in zip(heights, heights.dropFirst()) {
        let steps = max(1, Int((abs(next - from) / step).rounded()))
        altitudes += (1...steps).map { from + (next - from) * Double($0) / Double(steps) }
    }
    return altitudes.enumerated().map { index, altitude in
        let goingDown = index > 0 && altitude < altitudes[index - 1]
        return SlopeDay.Sample(seconds: Double(index) * 10, altitude: altitude, speed: speed.map { goingDown ? $0 : 4 })
    }
}

@Test func countsEachRunDownAndNotTheLiftsUp() throws {
    // Up the lift, down, up, down, up, down: three runs of 300, 250 and 200 metres.
    let skied = try #require(SlopeDay(day([1800, 2100, 1800, 2050, 1800, 2000, 1800])))
    #expect(skied.runs == 3)
    #expect(skied.descentM == 750)
    #expect(skied.topSpeedKmh == 43.2)
}

@Test func aWobbleOrAShortDipIsNoRun() {
    // GPS wobbling 8 metres on a flat, then a dip of 23 metres from its highest: no run at all.
    #expect(SlopeDay(day([1800, 1808, 1800, 1808, 1800, 1785, 1800], step: 2)) == nil)
    #expect(SlopeDay([]) == nil)
}

@Test func oneBadFixCannotMakeTheTopSpeed() throws {
    var samples = day([2100, 1800])
    samples[10] = SlopeDay.Sample(seconds: samples[10].seconds, altitude: samples[10].altitude, speed: 40)
    samples[12] = SlopeDay.Sample(seconds: samples[12].seconds, altitude: samples[12].altitude, speed: 90)
    let skied = try #require(SlopeDay(samples))
    #expect(skied.runs == 1)
    #expect(skied.topSpeedKmh == 43.2)
}

@Test func withoutSpeedsTheDayKeepsItsRunsAndDrop() throws {
    let skied = try #require(SlopeDay(day([2100, 1800], speed: nil)))
    #expect(skied.runs == 1)
    #expect(skied.topSpeedKmh == nil)
}

@Test func aSkiDayShowsItsRunsInPlaceOfHeartRate() throws {
    let skied = try #require(SlopeDay(day([1800, 2100, 1800])))
    let summary = WorkoutSummary(durationSec: 3600, avgHr: 130, maxHr: 170, effort: 6).skied(skied)
    #expect(summary.cells == [.duration, .runs, .descent, .topSpeed])
}
