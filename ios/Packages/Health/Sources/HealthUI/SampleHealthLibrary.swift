import Contracts
import Foundation
import HealthDomain

/// A day of workouts as Health would hand them over, for previews, the sample squad and UI tests
/// (`-health-sample`): a run with its route, a ski day, a strength session, a pool swim, yoga and
/// a ride, as in the approved prototypes. Connected from the start unless `connected` says otherwise.
public actor SampleHealthLibrary: HealthLibrary {
    private var connected: Bool
    private let workoutsEnding: Date

    /// - Parameter endingNear: about when the last of them ended; they are spread over the hours before.
    public init(connected: Bool = true, endingNear end: Date = Date()) {
        self.connected = connected
        workoutsEnding = end
    }

    public nonisolated var isAvailable: Bool { true }

    public func isConnected() -> Bool { connected }

    public func connect() -> Bool {
        connected = true
        return true
    }

    public func workouts(endingFrom start: Date, to end: Date) -> [ImportedWorkout] {
        guard connected else { return [] }
        return Self.day(endingNear: workoutsEnding).filter {
            $0.workout.endedAt.date >= start && $0.workout.endedAt.date <= end
        }
    }

    /// Six workouts, the newest ending a minute before `end`, the oldest about four hours before.
    public static func day(endingNear end: Date) -> [ImportedWorkout] {
        let samples = [
            Sample(
                id: "sample-bike", sport: "roadCycling", minutesAgo: 1,
                summary: WorkoutSummary(durationSec: 3060, distanceM: 18_200, speedKmh: 21.4, avgHr: 132),
                extra: .route(9)),
            Sample(
                id: "sample-yoga", sport: "yoga", minutesAgo: 50,
                summary: WorkoutSummary(durationSec: 3600, avgHr: 98, effort: 4), extra: .heartRate(11)),
            Sample(
                id: "sample-swim", sport: "swim", minutesAgo: 110,
                summary: WorkoutSummary(durationSec: 2400, distanceM: 1200, avgHr: 139, laps: 24, poolLengthM: 50),
                extra: .laps),
            Sample(
                id: "sample-strength", sport: "strength", minutesAgo: 170,
                summary: WorkoutSummary(durationSec: 2700, avgHr: 126, maxHr: 171, effort: 8), extra: .heartRate(7)),
            Sample(
                id: "sample-ski", sport: "ski", minutesAgo: 200,
                summary: WorkoutSummary(durationSec: 11_040, runs: 12, descentM: 1860, topSpeedKmh: 62.4),
                extra: .route(2)),
            Sample(
                id: "sample-run", sport: "run", minutesAgo: 240,
                summary: WorkoutSummary(durationSec: 1920, distanceM: 5200, paceSecPerKm: 369, avgHr: 148),
                extra: .route(4)),
        ]
        return samples.map { sample in
            let ended = end.addingTimeInterval(-sample.minutesAgo * 60)
            let seconds = Double(sample.summary.durationSec ?? 0)
            let started = ended.addingTimeInterval(-seconds)
            var series: WorkoutSeries?
            var route: [RoutePoint]?
            switch sample.extra {
            case .route(let seed):
                route = Self.loop(seed: seed)
                series = WorkoutSeries(heartRate: Self.heartRate(seconds: seconds, seed: seed))
            case .heartRate(let seed): series = WorkoutSeries(heartRate: Self.heartRate(seconds: seconds, seed: seed))
            case .laps: series = WorkoutSeries(laps: Self.laps)
            }
            return ImportedWorkout(
                workout: Workout(
                    source: WorkoutSource(provider: WorkoutSource.appleHealth, id: sample.id),
                    startedAt: Timestamp(started), endedAt: Timestamp(ended), summary: sample.summary,
                    series: series, route: route),
                activity: .sport(sample.sport))
        }
    }

    private struct Sample {
        let id: String
        let sport: Sport
        let minutesAgo: Double
        let summary: WorkoutSummary
        let extra: Extra
    }

    private enum Extra {
        /// A route and the heart rate along it.
        case route(Int)
        case heartRate(Int)
        case laps
    }

    /// Each lap of 24, the 17th the fastest.
    private static let laps: [Double] = (0..<24).map { (lap: Int) -> Double in
        guard lap != 16 else { return 44 }
        let spread: Int = (lap * 7) % 9
        return 50 + Double(spread)
    }

    /// A loop through a park in Manhattan, already trimmed.
    private static func loop(seed: Int) -> [RoutePoint] {
        (0...80).map { step in
            let turn: Double = Double(step) / 80 * 1.7 * Double.pi
            let angle: Double = turn + Double(seed) * 0.1
            let lat: Double = 40.7812 + 0.006 * sin(angle)
            let lon: Double = -73.9665 + 0.009 * cos(angle)
            return RoutePoint(lat: lat, lon: lon)
        }
    }

    /// A curve that warms up, wanders and eases off.
    private static func heartRate(seconds: Double, seed: Int) -> [HeartRatePoint] {
        let count = 120
        return (0..<count).map { index in
            let progress: Double = Double(index) / Double(count - 1)
            let fast: Double = sin(progress * 17 + Double(seed)) * 9
            let slow: Double = sin(progress * 5 + Double(seed) * 2) * 6
            let wander: Double = fast + slow
            let shape: Double = 95 + 50 * sin(progress * Double.pi)
            return HeartRatePoint(seconds: progress * seconds, bpm: Int(shape + wander))
        }
    }
}
