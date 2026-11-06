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
