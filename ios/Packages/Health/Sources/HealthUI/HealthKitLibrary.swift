#if canImport(HealthKit) && os(iOS)
import CoreLocation
import Contracts
import Foundation
import HealthDomain
import HealthKit

/// Apple Health through HealthKit, read only: the only code that knows HealthKit. Each workout
/// comes with the numbers Health has for its kind (a run's distance and pace, a ride's speed, a
/// pool swim's laps, heart rate and effort for all), its route trimmed 200 m at each end and
/// thinned, or its heart rate or lap times for the chart. Calories, weight and sleep are never
/// read. Its two lets, `HKHealthStore` and `UserDefaults`, are thread-safe per Apple.
public final class HealthKitLibrary: HealthLibrary, @unchecked Sendable {  // only thread-safe lets
    private let store: HKHealthStore
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        store = HKHealthStore()
        self.defaults = defaults
    }

    public var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    public func isConnected() async -> Bool {
        isAvailable && defaults.bool(forKey: Self.connectedKey)
    }

    public func connect() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: Self.readTypes)
            defaults.set(true, forKey: Self.connectedKey)
            return true
        } catch {
            return false
        }
    }

    public func workouts(endingFrom start: Date, to end: Date) async -> [ImportedWorkout] {
        guard await isConnected() else { return [] }
        let window = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictEndDate)
        let query = HKSampleQueryDescriptor(
            predicates: [.workout(window)], sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: Self.workoutsMax)
        guard let found = try? await query.result(for: store) else { return [] }
        var imported: [ImportedWorkout] = []
        for workout in found {
            imported.append(await self.imported(workout))
        }
        return imported
    }

    private func imported(_ workout: HKWorkout) async -> ImportedWorkout {
        let kind = WorkoutKind(workout.workoutActivityType)
        let seconds = workout.duration
        var summary = WorkoutSummary(durationSec: seconds >= 1 ? Int(seconds.rounded()) : nil)
        let heart = workout.statistics(for: HKQuantityType(.heartRate))
        let beats = HKUnit.count().unitDivided(by: .minute())
        if let average = heart?.averageQuantity()?.doubleValue(for: beats) { summary.avgHr = Self.bpm(average) }
        if kind.showsMaxHeartRate, let max = heart?.maximumQuantity()?.doubleValue(for: beats) {
            summary.maxHr = Self.bpm(max)
        }
        if kind.showsDistance, let distanceType = kind.distanceType,
            let meters = workout.statistics(for: distanceType)?.sumQuantity()?.doubleValue(for: .meter()), meters > 0
        {
            summary.distanceM = meters.rounded()
            let kilometres = meters / 1000
            switch kind {
            case .onFoot where kilometres >= 0.1 && seconds > 0: summary.paceSecPerKm = (seconds / kilometres).rounded()
            case .ride where seconds > 0: summary.speedKmh = ((kilometres / (seconds / 3600)) * 10).rounded() / 10
            default: break
            }
        }
        var series: WorkoutSeries?
        if kind == .swim, let pool = workout.metadata?[HKMetadataKeyLapLength] as? HKQuantity {
            let laps = (workout.workoutEvents ?? []).filter { $0.type == .lap }.map(\.dateInterval.duration)
            if !laps.isEmpty {
                summary.laps = laps.count
                summary.poolLengthM = pool.doubleValue(for: .meter()).rounded()
                series = WorkoutSeries(laps: laps.map { ($0 * 10).rounded() / 10 })
            }
        }
        if kind.showsEffort, let effort = await effort(of: workout) { summary.effort = effort }
        let route = kind.hasRoute ? await route(of: workout) : nil
        if route == nil, series == nil, let curve = await heartRate(during: workout) {
            series = WorkoutSeries(heartRate: curve)
        }
        return ImportedWorkout(
            workout: Workout(
                source: WorkoutSource(provider: WorkoutSource.appleHealth, id: workout.uuid.uuidString),
                startedAt: Timestamp(workout.startDate), endedAt: Timestamp(workout.endDate), summary: summary,
                series: series, route: route),
            activity: kind.sport(for: workout.workoutActivityType).map(Activity.sport))
    }

    /// How hard it felt, 1 to 10: the member's own rating, else the Watch's estimate.
    private func effort(of workout: HKWorkout) async -> Double? {
        for type in [HKQuantityType(.workoutEffortScore), HKQuantityType(.estimatedWorkoutEffortScore)] {
            let related = HKQuery.predicateForWorkoutEffortSamplesRelated(workout: workout, activity: nil)
            let query = HKSampleQueryDescriptor(
                predicates: [.quantitySample(type: type, predicate: related)], sortDescriptors: [], limit: 1)
            if let sample = try? await query.result(for: store).first {
                let score = sample.quantity.doubleValue(for: .appleEffortScore())
                if (1...10).contains(score) { return (score * 10).rounded() / 10 }
            }
        }
        return nil
    }

    /// The route, trimmed and thinned; nil without one or when it is too short to trim.
    private func route(of workout: HKWorkout) async -> [RoutePoint]? {
        let routes = HKSampleQueryDescriptor(
            predicates: [.workoutRoute(HKQuery.predicateForObjects(from: workout))], sortDescriptors: [], limit: 1)
        guard let route = try? await routes.result(for: store).first else { return nil }
        var points: [RoutePoint] = []
        do {
            for try await location in HKWorkoutRouteQueryDescriptor(route).results(for: store) {
                points.append(RoutePoint(lat: location.coordinate.latitude, lon: location.coordinate.longitude))
            }
        } catch {
            return nil
        }
        let kept = points.trimmed().thinned(to: Self.routePoints)
        return kept.count >= 2 ? kept : nil
    }

    /// Heart rate through the workout, thinned for the chart; nil with too few readings.
    private func heartRate(during workout: HKWorkout) async -> [HeartRatePoint]? {
        let during = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate)
        let query = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.heartRate), predicate: during)],
            sortDescriptors: [SortDescriptor(\.startDate)])
        guard let samples = try? await query.result(for: store) else { return nil }
        let beats = HKUnit.count().unitDivided(by: .minute())
        let points = samples.compactMap { sample -> HeartRatePoint? in
            guard let bpm = Self.bpm(sample.quantity.doubleValue(for: beats)) else { return nil }
            return HeartRatePoint(seconds: max(0, sample.startDate.timeIntervalSince(workout.startDate)), bpm: bpm)
        }
        return points.count >= 2 ? points.thinned() : nil
    }

    /// A reading the API keeps: 20 to 250.
    private static func bpm(_ value: Double) -> Int? {
        let rounded = Int(value.rounded())
        return (20...250).contains(rounded) ? rounded : nil
    }

    private static let readTypes: Set<HKObjectType> = [
        HKObjectType.workoutType(), HKSeriesType.workoutRoute(), HKQuantityType(.heartRate),
        HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling), HKQuantityType(.distanceSwimming),
        HKQuantityType(.workoutEffortScore), HKQuantityType(.estimatedWorkoutEffortScore),
    ]
    private static let connectedKey = "health.connected"
    private static let workoutsMax = 20
    /// Enough for a smooth line on a card; keeps the post small.
    private static let routePoints = 600
}

/// Which numbers a kind of workout shows, as the approved strips do (Tracy, 2026-11-06): a run
/// 距离 · 配速 · 平均心率, a ride 距离 · 均速 · 平均心率, a swim 趟数 · 距离 · 平均心率, yoga and the like
/// 平均心率 · 费力, everything else 平均心率 · 最高心率 · 费力; 时长 first always.
private enum WorkoutKind: Equatable {
    case onFoot, ride, swim, calm, other

    init(_ type: HKWorkoutActivityType) {
        switch type {
        case .running, .walking, .hiking, .wheelchairWalkPace, .wheelchairRunPace: self = .onFoot
        case .cycling, .handCycling: self = .ride
        case .swimming: self = .swim
        case .yoga, .pilates, .mindAndBody, .flexibility, .barre, .taiChi, .cooldown, .preparationAndRecovery:
            self = .calm
        default: self = .other
        }
    }

    var showsDistance: Bool { self == .onFoot || self == .ride || self == .swim }
    var showsMaxHeartRate: Bool { self == .other }
    var showsEffort: Bool { self == .calm || self == .other }
    /// Outdoor kinds may have a route; indoor ones get the chart instead.
    var hasRoute: Bool { self == .onFoot || self == .ride || self == .other }

    var distanceType: HKQuantityType? {
        switch self {
        case .onFoot: HKQuantityType(.distanceWalkingRunning)
        case .ride: HKQuantityType(.distanceCycling)
        case .swim: HKQuantityType(.distanceSwimming)
        case .calm, .other: nil
        }
    }

    /// The sport of the sports list it is; nil when the list has none like it.
    func sport(for type: HKWorkoutActivityType) -> Sport? {
        Self.sports[type].flatMap(Sport.init(rawValue:))
    }

    /// Health's kinds by the sports list's ids.
    private static let sports: [HKWorkoutActivityType: String] = [
        .running: "run", .walking: "walk", .hiking: "hike", .cycling: "roadCycling", .swimming: "swim",
        .traditionalStrengthTraining: "strength", .functionalStrengthTraining: "strength", .coreTraining: "strength",
        .crossTraining: "crossfit", .highIntensityIntervalTraining: "hiit", .rowing: "rowing",
        .elliptical: "elliptical", .jumpRope: "jumpRope", .mixedCardio: "aerobics", .stepTraining: "aerobics",
        .stairClimbing: "aerobics", .yoga: "yoga", .pilates: "matPilates", .barre: "barre",
        .flexibility: "stretching", .cooldown: "stretching", .tennis: "tennis", .badminton: "badminton",
        .pickleball: "pickleball", .tableTennis: "tableTennis", .squash: "squash", .basketball: "basketball",
        .soccer: "soccer", .volleyball: "volleyball", .golf: "golf", .climbing: "climb",
        .downhillSkiing: "ski", .crossCountrySkiing: "ski", .snowboarding: "snowboard", .skatingSports: "skate",
        .boxing: "boxing", .kickboxing: "kickboxing", .martialArts: "martialArts", .socialDance: "dance",
        .cardioDance: "dance", .surfingSports: "surf", .paddleSports: "paddleboard",
    ]
}
#endif
