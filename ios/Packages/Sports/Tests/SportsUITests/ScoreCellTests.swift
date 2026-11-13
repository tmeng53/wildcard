import Contracts
import SportsUI
import Testing

@Test func aRunReadsAsHealthGaveIt() {
    let cells = ScoreCell.cells(
        of: WorkoutSummary(durationSec: 1920, distanceM: 5210, paceSecPerKm: 369, avgHr: 148))
    #expect(cells.map(\.value) == ["32", "5.2", "6′09″", "148"])
    #expect(cells.map(\.unit) == [.minutes, .kilometres, nil, nil])
}

@Test func aPoolSwimCountsLapsAndMetres() {
    let cells = ScoreCell.cells(
        of: WorkoutSummary(durationSec: 2400, distanceM: 1200, avgHr: 139, laps: 24, poolLengthM: 50))
    #expect(cells.map(\.value) == ["40", "24", "1200", "139"])
    #expect(cells[1].label == .laps(poolMeters: 50))
    #expect(cells[2].unit == .meters)
}

@Test func aRideShowsItsSpeedAndEffortDropsAWholeNumbersPoint() {
    let ride = ScoreCell.cells(of: WorkoutSummary(durationSec: 3060, speedKmh: 21.44))
    #expect(ride.last?.value == "21.4")
    #expect(ScoreCell.cells(of: WorkoutSummary(effort: 7)).map(\.value) == ["7"])
    #expect(ScoreCell.cells(of: WorkoutSummary(effort: 7.5)).map(\.value) == ["7.5"])
}

@Test func aHandMadePostShowsItsMinutesAloneOrNoStrip() throws {
    let timed = Training(activity: .sport("tennis"), minutes: try WorkoutMinutes(45))
    #expect(ScoreCell.cells(of: timed).map(\.value) == ["45"])
    #expect(ScoreCell.cells(of: Training(activity: .sport("tennis"))).isEmpty)
}

@Test func everyLapBarFitsTheChartHoweverManyLapsThereAre() {
    for count in [1, 8, 40, 200] {
        let bars = LapBars.across(64, count: count)
        #expect(bars.count == count)
        #expect(bars.allSatisfy { $0.start >= 0 && $0.width > 0 && $0.start + $0.width <= 64.000_001 })
    }
    let two = LapBars.across(64, count: 2)
    #expect(two.map(\.start) == [0, 32])
    #expect(two.allSatisfy { abs($0.width - 22.4) < 0.000_001 })
}

@Test func aSkiDayShowsItsRunsDropAndTopSpeed() {
    let cells = ScoreCell.cells(
        of: WorkoutSummary(durationSec: 11_040, runs: 12, descentM: 1860.4, topSpeedKmh: 62.44))
    #expect(cells.map(\.value) == ["184", "12", "1,860", "62.4"])
    #expect(cells.map(\.unit) == [.minutes, .runs, .meters, .kilometresPerHour])
    #expect(cells.map(\.label) == [.duration, .runs, .descent, .topSpeed])
}

@Test func aHikeShowsItsClimbAndAnOpenWaterSwimItsPacePer100Metres() {
    let hike = ScoreCell.cells(
        of: WorkoutSummary(durationSec: 12_600, distanceM: 12_600, avgHr: 118, elevationGainM: 840))
    #expect(hike.map(\.value) == ["210", "12.6", "840", "118"])
    #expect(hike[2].label == .elevationGain)
    let swim = ScoreCell.cells(of: WorkoutSummary(durationSec: 2520, distanceM: 1800, avgHr: 136, paceSecPer100m: 140))
    #expect(swim.map(\.value) == ["42", "1.8", "2′20″", "136"])
    #expect(swim[2].unit == .per100Meters)
}

@Test func caloriesComeLastInWholeKilocalories() {
    let cells = ScoreCell.cells(
        of: WorkoutSummary(durationSec: 3540, avgHr: 124, maxHr: 156, activeEnergyKcal: 1312.6))
    #expect(cells.map(\.value) == ["59", "124", "156", "1,313"])
    #expect(cells.last?.unit == .kilocalories)
    #expect(cells.last?.label == .calories)
}

@Test func aRatedMealShowsHealthyAndTastyInStarsThenItsCalorieValue() throws {
    let cells = MealScoreCell.cells(of: try MealRating(healthy: 5, tasty: 4))
    #expect(cells.map(\.label) == [.healthy, .tasty, .calorieValue])
    #expect(cells.map(\.value) == ["5", "4", "4.0"])
    #expect(cells.map(\.isStars) == [true, true, false])
    #expect(MealScoreCell.cells(of: try MealRating(healthy: 3, tasty: 2)).last?.value == "1.2")
}
