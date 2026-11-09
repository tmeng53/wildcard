#if canImport(HealthKit) && os(iOS)
import CoreLocation
import Contracts
import Foundation
import HealthDomain
import HealthKit

/// Apple Health through HealthKit, read only: the only code that knows HealthKit. Each workout
/// comes with the numbers Health has for its kind (a run's distance and pace, a ride's speed, a
/// pool swim's laps, heart rate and effort for all), its route trimmed 200 m at each end and
/// thinned, its heart rate or lap times for the chart, its active calories, and the member's
/// latest resting heart rate, which with their birthday on their profile places the chart's zones
/// (only the zones are posted). Their date of birth, weight and sleep are never read. Its two
/// lets, `HKHealthStore` and `UserDefaults`, are thread-safe per Apple, and the rest are constants.
public final class HealthKitLibrary: HealthLibrary, @unchecked Sendable {  // only thread-safe lets
    private let store: HKHealthStore
    private let defaults: UserDefaults
    private let detail: Detail
    private let asksForNewTypes: Bool

    /// - Parameters:
    ///   - detail: how much of each workout to read.
    ///   - asksForNewTypes: whether a read asks for read types added since the member connected;
    ///     only the app can show Health's sheet, so an extension passes false.
    public init(defaults: UserDefaults = .standard, detail: Detail = .full, asksForNewTypes: Bool = true) {
        store = HKHealthStore()
        self.defaults = defaults
        self.detail = detail
        self.asksForNewTypes = asksForNewTypes
    }

    public var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    public func isConnected() async -> Bool {
        isAvailable && defaults.bool(forKey: HealthKeys.connected)
    }

    public func connect() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: Self.readTypes)
            defaults.set(true, forKey: HealthKeys.connected)
            return true
        } catch {
            return false
        }
    }

    /// A member who connected before this build added a read type (active calories, resting heart rate) was never
    /// asked for it; Health shows its sheet again for just the new types, once.
    private func askForTypesAddedSinceConnecting() async {
        let status = try? await store.statusForAuthorizationRequest(toShare: [], read: Self.readTypes)
        guard status == .shouldRequest else { return }
        try? await store.requestAuthorization(toShare: [], read: Self.readTypes)
    }

    public func workouts(endingFrom start: Date, to end: Date) async -> [ImportedWorkout] {
        guard await isConnected() else { return [] }
        if asksForNewTypes { await askForTypesAddedSinceConnecting() }
        let window = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictEndDate)
        let query = HKSampleQueryDescriptor(
            predicates: [.workout(window)], sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: Self.workoutsMax)
        guard let found = try? await query.result(for: store) else { return [] }
        let resting = detail == .full ? await restingHeartRate(before: end) : nil
        var imported: [ImportedWorkout] = []
        for workout in found {
            imported.append(await self.imported(workout, resting: resting))
        }
        return imported
    }

    /// The newest resting heart rate Health has from the month before `end`.
    private func restingHeartRate(before end: Date) async -> Int? {
        let month = HKQuery.predicateForSamples(withStart: end.addingTimeInterval(-30 * 24 * 3600), end: end)
        let query = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.restingHeartRate), predicate: month)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)], limit: 1)
        guard let sample = try? await query.result(for: store).first else { return nil }
        return Self.bpm(sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())))
    }

    private func imported(_ workout: HKWorkout, resting: Int?) async -> ImportedWorkout {
        let type = workout.workoutActivityType
        let kind = WorkoutKind(type, openWater: Self.isOpenWater(workout))
        let seconds = workout.duration
        var summary = WorkoutSummary(durationSec: seconds >= 1 ? Int(seconds.rounded()) : nil)
        await addHeartRate(of: workout, kind: kind, to: &summary)
        Self.addDistance(of: workout, kind: kind, to: &summary)
        Self.addCalories(of: workout, to: &summary)
        var series = kind == .poolSwim ? Self.addLaps(of: workout, to: &summary) : nil
        if kind.showsEffort, let effort = await effort(of: workout) { summary.effort = effort }
        let route = detail == .full && kind.hasRoute ? await route(of: workout) : nil
        // A ski day's 趟数 · 落差 · 最高速 come from the route's heights and speeds, on the phone.
        if kind == .slope, let slopes = route?.slopes, let day = SlopeDay(slopes) { summary = summary.skied(day) }
        // With a route too, so a post can show the map and the heart rate (Tracy, 2026-11-07).
        if detail == .full, series == nil, let curve = await heartRate(during: workout) {
            series = WorkoutSeries(heartRate: curve)
        }
        return ImportedWorkout(
            workout: Workout(
                source: WorkoutSource(provider: WorkoutSource.appleHealth, id: workout.uuid.uuidString),
                startedAt: Timestamp(workout.startDate), endedAt: Timestamp(workout.endDate), summary: summary,
                series: series, route: route?.points),
            activity: WorkoutKind.sport(for: type).map(Activity.sport),
            restingBpm: series?.heartRate == nil ? nil : resting)
    }

    /// Its average heart rate, and its highest where its kind shows that: the workout's own
    /// statistics, else Health's statistics of the heart-rate readings while it ran, since a
    /// workout another app saved may come without its own.
    private func addHeartRate(of workout: HKWorkout, kind: WorkoutKind, to summary: inout WorkoutSummary) async {
        let heart: HKStatistics?
        if let own = workout.statistics(for: HKQuantityType(.heartRate)), own.averageQuantity() != nil {
            heart = own
        } else {
            heart = await heartRateStatistics(during: workout)
        }
        let beats = HKUnit.count().unitDivided(by: .minute())
        if let average = heart?.averageQuantity()?.doubleValue(for: beats) { summary.avgHr = Self.bpm(average) }
        if kind.showsMaxHeartRate, let max = heart?.maximumQuantity()?.doubleValue(for: beats) {
            summary.maxHr = Self.bpm(max)
        }
    }

    /// Health's average and highest of the heart-rate readings from the workout's start to its end.
    private func heartRateStatistics(during workout: HKWorkout) async -> HKStatistics? {
        let during = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate)
        let query = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(.heartRate), predicate: during),
            options: [.discreteAverage, .discreteMax])
        return try? await query.result(for: store)
    }

    /// The active energy Health has for it, in kilocalories, as the Fitness app shows it.
    private static func addCalories(of workout: HKWorkout, to summary: inout WorkoutSummary) {
        let burned = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()
        if let kcal = burned?.doubleValue(for: .kilocalorie()), kcal >= 1 { summary.activeEnergyKcal = kcal.rounded() }
    }

    /// A pool swim's laps with the pool's length, and each lap's time for its chart; nil without.
    private static func addLaps(of workout: HKWorkout, to summary: inout WorkoutSummary) -> WorkoutSeries? {
        guard let pool = workout.metadata?[HKMetadataKeyLapLength] as? HKQuantity else { return nil }
        let laps = (workout.workoutEvents ?? []).filter { $0.type == .lap }.map(\.dateInterval.duration)
        guard !laps.isEmpty else { return nil }
        summary.laps = laps.count
        summary.poolLengthM = pool.doubleValue(for: .meter()).rounded()
        return WorkoutSeries(laps: laps.map { ($0 * 10).rounded() / 10 })
    }

    /// Its distance, with the pace or speed that goes with it, and a hike's climb.
    private static func addDistance(of workout: HKWorkout, kind: WorkoutKind, to summary: inout WorkoutSummary) {
        let seconds = workout.duration
        let meters = kind.distanceTypes(for: workout.workoutActivityType).compactMap {
            workout.statistics(for: $0)?.sumQuantity()?.doubleValue(for: .meter())
        }.reduce(0, +)
        if meters > 0 {
            summary.distanceM = meters.rounded()
            let kilometres = meters / 1000
            switch kind {
            case .onFoot where kilometres >= 0.1 && seconds > 0: summary.paceSecPerKm = (seconds / kilometres).rounded()
            case .openWaterSwim where meters >= 100 && seconds > 0:
                summary.paceSecPer100m = (seconds / (meters / 100)).rounded()
            case .ride, .glide:
                if seconds > 0 { summary.speedKmh = (kilometres / (seconds / 3600) * 10).rounded() / 10 }
            default: break
            }
        }
        if kind == .hike, let climbed = workout.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity {
            let gain = climbed.doubleValue(for: .meter())
            if gain >= 1 { summary.elevationGainM = gain.rounded() }
        }
    }

    /// A swim in open water, which Health marks; a pool swim otherwise.
    private static func isOpenWater(_ workout: HKWorkout) -> Bool {
        let location = (workout.metadata?[HKMetadataKeySwimmingLocationType] as? NSNumber)?.intValue
        return location == HKWorkoutSwimmingLocationType.openWater.rawValue
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

    /// The route, trimmed and thinned, with its heights and speeds for a ski day, read before
    /// the trim (the points posted keep only where they were); nil without one.
    private func route(of workout: HKWorkout) async -> (points: [RoutePoint]?, slopes: [SlopeDay.Sample])? {
        let routes = HKSampleQueryDescriptor(
            predicates: [.workoutRoute(HKQuery.predicateForObjects(from: workout))], sortDescriptors: [], limit: 1)
        guard let route = try? await routes.result(for: store).first else { return nil }
        var points: [RoutePoint] = []
        var slopes: [SlopeDay.Sample] = []
        do {
            for try await location in HKWorkoutRouteQueryDescriptor(route).results(for: store) {
                points.append(RoutePoint(lat: location.coordinate.latitude, lon: location.coordinate.longitude))
                // A negative accuracy means the reading has no height, a negative speed none.
                if location.verticalAccuracy >= 0 {
                    slopes.append(
                        SlopeDay.Sample(
                            seconds: location.timestamp.timeIntervalSince(workout.startDate),
                            altitude: location.altitude, speed: location.speed >= 0 ? location.speed : nil))
                }
            }
        } catch {
            return nil
        }
        let kept = points.trimmed().thinned(to: Self.routePoints)
        return (kept.count >= 2 ? kept : nil, slopes)
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
        HKQuantityType(.distanceCrossCountrySkiing), HKQuantityType(.distanceRowing),
        HKQuantityType(.distancePaddleSports), HKQuantityType(.distanceSkatingSports),
        HKQuantityType(.distanceWheelchair), HKQuantityType(.workoutEffortScore),
        HKQuantityType(.estimatedWorkoutEffortScore), HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.restingHeartRate),
    ]
    private static let workoutsMax = 20
    /// Enough for a smooth line on a card; keeps the post small.
    private static let routePoints = 600
}

/// Which numbers a kind of workout shows, as the approved strips do (Tracy, 2026-11-06 and
/// 2026-11-08), 时长 first always: a run or walk 距离 · 配速 · 平均心率, a hike 距离 · 爬升 · 平均心率,
/// a ride 距离 · 均速 · 平均心率, a pool swim 趟数 · 距离 · 平均心率, an open-water swim 距离 · 配速
/// /100 米 · 平均心率, a ski or snowboard day 趟数 · 落差 · 最高速 (worked out from its route, else as
/// other kinds), cross-country skiing, rowing, paddling and skating 距离 · 均速 · 平均心率, a
/// triathlon 距离 · 平均心率 · 最高心率, yoga and the like 平均心率 · 强度, everything else 平均心率 ·
/// 最高心率 · 强度.
private enum WorkoutKind: Equatable {
    case onFoot, hike, ride, poolSwim, openWaterSwim, slope, glide, triathlon, calm, other

    init(_ type: HKWorkoutActivityType, openWater: Bool) {
        switch type {
        case .running, .walking, .wheelchairWalkPace, .wheelchairRunPace, .trackAndField: self = .onFoot
        case .hiking: self = .hike
        case .cycling, .handCycling: self = .ride
        case .swimming: self = openWater ? .openWaterSwim : .poolSwim
        case .downhillSkiing, .snowboarding: self = .slope
        case .crossCountrySkiing, .rowing, .paddleSports, .skatingSports: self = .glide
        case .swimBikeRun: self = .triathlon
        case .yoga, .pilates, .mindAndBody, .flexibility, .barre, .taiChi, .cooldown, .preparationAndRecovery:
            self = .calm
        default: self = .other
        }
    }

    /// A ski day without the route to work out its runs shows what other kinds do.
    var showsMaxHeartRate: Bool { [.other, .slope, .triathlon].contains(self) }
    var showsEffort: Bool { [.calm, .other, .slope].contains(self) }
    /// Outdoor kinds may have a route; indoor ones get the chart instead.
    var hasRoute: Bool { ![.poolSwim, .calm].contains(self) }

    /// Where Health keeps its distance: a triathlon's is its legs' added up.
    func distanceTypes(for type: HKWorkoutActivityType) -> [HKQuantityType] {
        switch (self, type) {
        case (.onFoot, .wheelchairWalkPace), (.onFoot, .wheelchairRunPace): [HKQuantityType(.distanceWheelchair)]
        case (.onFoot, _), (.hike, _): [HKQuantityType(.distanceWalkingRunning)]
        case (.ride, _): [HKQuantityType(.distanceCycling)]
        case (.poolSwim, _), (.openWaterSwim, _): [HKQuantityType(.distanceSwimming)]
        case (.glide, .crossCountrySkiing): [HKQuantityType(.distanceCrossCountrySkiing)]
        case (.glide, .rowing): [HKQuantityType(.distanceRowing)]
        case (.glide, .paddleSports): [HKQuantityType(.distancePaddleSports)]
        case (.glide, _): [HKQuantityType(.distanceSkatingSports)]
        case (.triathlon, _):
            [
                HKQuantityType(.distanceSwimming), HKQuantityType(.distanceCycling),
                HKQuantityType(.distanceWalkingRunning),
            ]
        case (.slope, _), (.calm, _), (.other, _): []
        }
    }

    /// The sport of the sports list each kind of Health workout is (Tracy, 2026-11-08: every one
    /// has one); nil only for 其他, which the member picks.
    static func sport(for type: HKWorkoutActivityType) -> Sport? {
        sportID(for: type).flatMap(Sport.init(rawValue:))
    }

    // Every kind Health has; one a later iOS adds is 其他 until it is listed here.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private static func sportID(for type: HKWorkoutActivityType) -> String? {
        switch type {
        case .running, .trackAndField, .wheelchairRunPace: "run"
        case .walking, .wheelchairWalkPace: "walk"
        case .hiking: "hike"
        case .swimBikeRun, .transition: "triathlon"
        case .traditionalStrengthTraining, .functionalStrengthTraining, .coreTraining: "strength"
        case .crossTraining: "crossfit"
        case .gymnastics: "gymnastics"
        case .cycling, .handCycling: "roadCycling"
        case .highIntensityIntervalTraining: "hiit"
        case .rowing: "rowing"
        case .elliptical: "elliptical"
        case .jumpRope: "jumpRope"
        case .mixedCardio, .stepTraining: "aerobics"
        case .stairClimbing, .stairs: "stairs"
        case .fitnessGaming: "fitnessGaming"
        case .yoga, .mindAndBody: "yoga"
        case .pilates: "matPilates"
        case .barre: "barre"
        case .flexibility, .cooldown, .preparationAndRecovery: "stretching"
        case .taiChi: "taiChi"
        case .swimming: "swim"
        case .surfingSports: "surf"
        case .paddleSports: "paddleboard"
        case .underwaterDiving: "diving"
        case .sailing: "sailing"
        case .waterFitness: "waterFitness"
        case .waterPolo: "waterPolo"
        case .waterSports: "waterSports"
        case .tennis: "tennis"
        case .badminton: "badminton"
        case .pickleball: "pickleball"
        case .tableTennis: "tableTennis"
        case .squash: "squash"
        case .racquetball: "racquetball"
        case .basketball: "basketball"
        case .soccer: "soccer"
        case .volleyball: "volleyball"
        case .golf: "golf"
        case .baseball, .softball: "baseballSoftball"
        case .discSports: "ultimate"
        case .americanFootball: "americanFootball"
        case .rugby, .australianFootball: "rugby"
        case .hockey: "hockey"
        case .lacrosse: "lacrosse"
        case .cricket: "cricket"
        case .handball: "handball"
        case .bowling: "bowling"
        case .climbing: "climb"
        case .archery: "archery"
        case .equestrianSports: "horseRiding"
        case .fishing: "fishing"
        case .hunting: "hunting"
        case .downhillSkiing: "ski"
        case .snowboarding: "snowboard"
        case .crossCountrySkiing: "crossCountrySki"
        case .skatingSports: "skate"
        case .curling: "curling"
        case .snowSports: "snowHike"
        case .boxing: "boxing"
        case .kickboxing: "kickboxing"
        case .martialArts: "martialArts"
        case .fencing: "fencing"
        case .wrestling: "wrestling"
        case .socialDance, .cardioDance: "dance"
        case .play: "play"
        case .other: nil
        default: retiredSportID(rawValue: type.rawValue)
        }
    }

    /// Kinds Apple retired, which older apps may still write, by their raw values (naming them
    /// warns): dance (14) and dance-inspired training (15) are 跳舞, mixed metabolic cardio (30) 有氧操.
    private static func retiredSportID(rawValue: UInt) -> String? {
        switch rawValue {
        case 14, 15: "dance"
        case 30: "aerobics"
        default: nil
        }
    }
}
#endif
