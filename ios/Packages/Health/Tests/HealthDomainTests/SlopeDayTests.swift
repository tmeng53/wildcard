import Contracts
import HealthDomain
import Testing

/// Readings every 10 seconds through `heights`, a minute at each (getting off the lift, waiting
/// at the bottom), each leg in even steps of `step` metres, at `speed` m/s going down and 4 m/s on
/// the way up.
private func day(_ heights: [Double], step: Double = 10, speed: Double? = 12) -> [SlopeDay.Sample] {
    var altitudes = Array(repeating: heights[0], count: 7)
    for (from, next) in zip(heights, heights.dropFirst()) {
        let steps = max(1, Int((abs(next - from) / step).rounded()))
        altitudes += (1...steps).map { from + (next - from) * Double($0) / Double(steps) }
        altitudes += Array(repeating: next, count: 6)
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

@Test func twoBadFixesInARowCannotMakeTheTopSpeed() throws {
    var samples = day([2100, 1800])
    for index in [12, 13] {
        samples[index] = SlopeDay.Sample(seconds: samples[index].seconds, altitude: samples[index].altitude, speed: 40)
    }
    samples[20] = SlopeDay.Sample(seconds: samples[20].seconds, altitude: samples[20].altitude, speed: 90)
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

@Test func aTraverseUphillMidRunIsStillOneRun() throws {
    // Down 200, up 25 across a flat, down 150: one run, its drop top to foot.
    let skied = try #require(SlopeDay(day([1800, 2200, 2000, 2025, 1875])))
    #expect(skied.runs == 1)
    #expect(skied.descentM == 325)
}

@Test func noisyHeightsKeepTheRunsAndTheirDrop() throws {
    // Two runs of 300 metres, every height off by up to 25 metres either way.
    var seed: UInt64 = 42
    let noisy = day([1800, 2100, 1800, 2100, 1800]).map { sample in
        seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        let wobble = Double(seed >> 33) / Double(UInt64(1) << 31) * 50 - 25
        return SlopeDay.Sample(seconds: sample.seconds, altitude: sample.altitude + wobble, speed: sample.speed)
    }
    let skied = try #require(SlopeDay(noisy))
    #expect(skied.runs == 2)
    #expect(abs(skied.descentM - 600) <= 60)
}
