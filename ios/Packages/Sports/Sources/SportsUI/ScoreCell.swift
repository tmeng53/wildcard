import Contracts
import Foundation

/// One cell of a 成绩条: the number as Health gave it, its unit and what it is.
public struct ScoreCell: Hashable, Identifiable, Sendable {
    public enum Unit: Hashable, Sendable {
        case minutes, laps, runs, meters, kilometres, kilometresPerHour, per100Meters, outOfTen, kilocalories
    }

    public enum Label: Hashable, Sendable {
        case duration, distance, pace, speed, averageHeartRate, maxHeartRate, effort
        case runs, descent, topSpeed, elevationGain, calories
        /// Laps, with the pool's length when Health has it.
        case laps(poolMeters: Int?)
    }

    public let cell: WorkoutCell
    public let value: String
    public let unit: Unit?
    public let label: Label

    public var id: WorkoutCell { cell }

    public init(cell: WorkoutCell, value: String, unit: Unit?, label: Label) {
        self.cell = cell
        self.value = value
        self.unit = unit
        self.label = label
    }

    /// A 训练's cells: its workout's numbers, 时长 first, or a hand-made post's minutes alone;
    /// none when it has neither.
    public static func cells(of training: Training) -> [ScoreCell] {
        if let workout = training.workout { return cells(of: workout.summary) }
        guard let minutes = training.minutes else { return [] }
        return [ScoreCell(cell: .duration, value: "\(minutes.value)", unit: .minutes, label: .duration)]
    }

    // One case a cell.
    // swiftlint:disable cyclomatic_complexity function_body_length
    /// Each number a workout has, in the strip's order, never converted.
    public static func cells(of summary: WorkoutSummary) -> [ScoreCell] {
        summary.cells.compactMap { cell in
            switch cell {
            case .duration:
                summary.durationSec.map {
                    ScoreCell(
                        cell: cell, value: "\(max(1, Int((Double($0) / 60).rounded())))", unit: .minutes,
                        label: .duration)
                }
            case .laps:
                summary.laps.map {
                    ScoreCell(
                        cell: cell, value: "\($0)", unit: .laps,
                        label: .laps(poolMeters: summary.poolLengthM.map { Int($0.rounded()) }))
                }
            case .distance:
                summary.distanceM.map { meters in
                    // A pool swim reads in metres; anything else in kilometres.
                    summary.laps != nil || summary.poolLengthM != nil
                        ? ScoreCell(cell: cell, value: "\(Int(meters.rounded()))", unit: .meters, label: .distance)
                        : ScoreCell(
                            cell: cell, value: String(format: "%.1f", meters / 1000), unit: .kilometres,
                            label: .distance)
                }
            case .runs:
                summary.runs.map { ScoreCell(cell: cell, value: "\($0)", unit: .runs, label: .runs) }
            case .descent:
                summary.descentM.map {
                    ScoreCell(cell: cell, value: grouped(Int($0.rounded())), unit: .meters, label: .descent)
                }
            case .elevationGain:
                summary.elevationGainM.map {
                    ScoreCell(cell: cell, value: grouped(Int($0.rounded())), unit: .meters, label: .elevationGain)
                }
            case .pace:
                summary.paceSecPerKm.map {
                    ScoreCell(cell: cell, value: minutesAndSeconds($0), unit: nil, label: .pace)
                }
            case .swimPace:
                summary.paceSecPer100m.map {
                    ScoreCell(cell: cell, value: minutesAndSeconds($0), unit: .per100Meters, label: .pace)
                }
            case .speed:
                summary.speedKmh.map {
                    ScoreCell(
                        cell: cell, value: String(format: "%.1f", $0), unit: .kilometresPerHour, label: .speed)
                }
            case .topSpeed:
                summary.topSpeedKmh.map {
                    ScoreCell(
                        cell: cell, value: String(format: "%.1f", $0), unit: .kilometresPerHour, label: .topSpeed)
                }
            case .averageHeartRate:
                summary.avgHr.map { ScoreCell(cell: cell, value: "\($0)", unit: nil, label: .averageHeartRate) }
            case .maxHeartRate:
                summary.maxHr.map { ScoreCell(cell: cell, value: "\($0)", unit: nil, label: .maxHeartRate) }
            case .effort:
                summary.effort.map {
                    ScoreCell(
                        cell: cell, value: $0.rounded() == $0 ? "\(Int($0))" : String(format: "%.1f", $0),
                        unit: .outOfTen, label: .effort)
                }
            case .calories:
                summary.activeEnergyKcal.map {
                    ScoreCell(cell: cell, value: grouped(Int($0.rounded())), unit: .kilocalories, label: .calories)
                }
            }
        }
    }
    // swiftlint:enable cyclomatic_complexity function_body_length
}

/// A pace as minutes and seconds, 6′09″.
private func minutesAndSeconds(_ pace: Double) -> String {
    let seconds = Int(pace.rounded())
    return String(format: "%d′%02d″", seconds / 60, seconds % 60)
}

/// A whole number with its thousands marked, 1,860: the same in every language the app speaks.
private func grouped(_ number: Int) -> String {
    let digits = String(number.magnitude)
    var groups: [Substring] = []
    var end = digits.endIndex
    while end > digits.startIndex {
        let start = digits.index(end, offsetBy: -3, limitedBy: digits.startIndex) ?? digits.startIndex
        groups.insert(digits[start..<end], at: 0)
        end = start
    }
    return (number < 0 ? "-" : "") + groups.joined(separator: ",")
}
