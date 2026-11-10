import Contracts
import Foundation

/// A workout as it comes from Health, before the member posts it: every number Health has for
/// its kind of sport, the route already trimmed, the heart rate thinned, and the sport of the
/// sports list it is (nil when the list has none like it).
public struct ImportedWorkout: Hashable, Sendable, Identifiable {
    /// Its numbers, series and route; no tile position yet: the compose page places the tile.
    public let workout: Workout
    public let activity: Activity?
    /// The member's latest resting heart rate in Health when the workout has a heart-rate curve;
    /// it stays on the phone and only places the chart's zones.
    public let restingBpm: Int?

    public init(workout: Workout, activity: Activity?, restingBpm: Int? = nil) {
        self.workout = workout
        self.activity = activity
        self.restingBpm = restingBpm
    }

    /// The workout with its heart-rate zones placed for a member born on `birthday`, at their age
    /// on the day it started on `timeZone`'s clock; unchanged without a birthday or a heart-rate
    /// curve. Only the zones are posted, never the birthday or the resting heart rate.
    public func withZones(birthday: Birthday?, in timeZone: TimeZone) -> ImportedWorkout {
        guard let series = workout.series, let curve = series.heartRate, let birthday,
            let zones = HeartRateZones(
                age: birthday.age(on: LocalDay(at: workout.startedAt.date, in: timeZone)), restingBpm: restingBpm)
        else { return self }
        let zoned = Workout(
            source: workout.source, startedAt: workout.startedAt, endedAt: workout.endedAt, summary: workout.summary,
            series: WorkoutSeries(heartRate: curve, laps: series.laps, zones: zones), route: workout.route,
            tilePosition: workout.tilePosition, chartPosition: workout.chartPosition)
        return ImportedWorkout(workout: zoned, activity: activity, restingBpm: restingBpm)
    }

    public var id: WorkoutSource { workout.source }

    /// Whole minutes, for the chip and the post's `minutes`, which builds from before workouts
    /// read: at least 1, at most the API's 600.
    public var minutes: WorkoutMinutes? {
        guard let seconds = workout.summary.durationSec else { return nil }
        let rounded = Int((Double(seconds) / 60).rounded())
        return try? WorkoutMinutes(min(max(rounded, WorkoutMinutes.range.lowerBound), WorkoutMinutes.range.upperBound))
    }
}

/// Which numbers a post from Health carries unless the member strikes them (设置 › Apple 健康,
/// 「发动态时显示」): all on until switched off. 时长 starts kept, and is struck per post. Kept on the phone, with a
/// `version` as stored JSON.
public struct HealthSharing: Hashable, Sendable, Codable {
    public var version = 1
    /// 距离, and a hike's 爬升 and a ski day's 落差.
    public var distance = true
    /// 配速 for a run, walk or swim, 均速 for a ride, 最高速 on a ski day.
    public var pace = true
    public var heartRate = true
    public var effort = true
    /// A swim's 趟数, and a ski day's runs.
    public var laps = true
    public var route = true
    /// 卡路里, the active energy (Tracy, 2026-11-08); on for settings kept before it.
    public var calories = true

    public init() {}

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        distance = try values.decode(Bool.self, forKey: .distance)
        pace = try values.decode(Bool.self, forKey: .pace)
        heartRate = try values.decode(Bool.self, forKey: .heartRate)
        effort = try values.decode(Bool.self, forKey: .effort)
        laps = try values.decode(Bool.self, forKey: .laps)
        route = try values.decode(Bool.self, forKey: .route)
        calories = try values.decodeIfPresent(Bool.self, forKey: .calories) ?? true
    }

    /// The cells a new post from Health starts with struck.
    public var struck: Set<WorkoutCell> {
        var cells: Set<WorkoutCell> = []
        if !distance { cells.formUnion([.distance, .descent, .elevationGain]) }
        if !pace { cells.formUnion([.pace, .swimPace, .speed, .topSpeed]) }
        if !heartRate { cells.formUnion([.averageHeartRate, .maxHeartRate]) }
        if !effort { cells.insert(.effort) }
        if !laps { cells.formUnion([.laps, .runs]) }
        if !calories { cells.insert(.calories) }
        return cells
    }

    /// The tiles a new post from `workout` starts with: the map follows 路线, a lap chart
    /// 趟数 and a heart-rate chart 心率.
    public func keptTiles(of workout: Workout) -> [WorkoutTile] {
        workout.tiles.filter { tile in
            switch tile {
            case .map: route
            case .chart: workout.series?.laps?.isEmpty == false ? laps : heartRate
            }
        }
    }
}

/// Health on this phone: whether the member connected it, and their workouts. Read only. The app
/// passes HealthKit (`HealthUI`'s `HealthKitLibrary`); previews and UI tests a sample one.
public protocol HealthLibrary: Sendable {
    /// Whether this device has Health at all (an iPad may not).
    var isAvailable: Bool { get }
    /// Whether the member went through 连接 on this phone. Health never says whether reading was
    /// allowed: denied reads just come back empty.
    func isConnected() async -> Bool
    /// Asks the system for reading access, once; true once it was asked.
    func connect() async -> Bool
    /// The workouts that ended from `start` to `end`, the newest first.
    func workouts(endingFrom start: Date, to end: Date) async -> [ImportedWorkout]
}

/// Today's workouts as 打卡 shows them: each with whether it was posted already.
public struct TodaysWorkout: Hashable, Sendable, Identifiable {
    public let imported: ImportedWorkout
    public let isPosted: Bool

    public init(imported: ImportedWorkout, isPosted: Bool) {
        self.imported = imported
        self.isPosted = isPosted
    }

    public var id: WorkoutSource { imported.id }
}

/// A 训练 the member posted, as what is offered from Health is checked against it: its sport,
/// the day it counts for, when it was made and the Health workout it came from, if any.
public struct PostedTraining: Hashable, Sendable {
    public let activity: Activity
    public let day: LocalDay
    public let madeAt: Timestamp
    public let workout: Workout?

    public init(activity: Activity, day: LocalDay, madeAt: Timestamp, workout: Workout?) {
        self.activity = activity
        self.day = day
        self.madeAt = madeAt
        self.workout = workout
    }

    /// Whether this post is of `imported`'s session: its workout, or a workout of the same
    /// sport at an overlapping time, which is the same session saved again under another id
    /// (two apps saving it, or one saving it again after deleting it).
    func covers(_ imported: ImportedWorkout) -> Bool {
        guard let workout else { return false }
        if workout.source == imported.id { return true }
        return activity == imported.activity && workout.startedAt < imported.workout.endedAt
            && imported.workout.startedAt < workout.endedAt
    }
}

extension [ImportedWorkout] {
    /// Those that ended on the member's `day`, newest first, each marked posted when one of
    /// `posted` is of its session (a member posts each session once), or when a 训练 posted by
    /// hand that day covers it: each covers the earliest unposted workout of its sport that
    /// started before it was made.
    public func today(_ day: LocalDay, in timeZone: TimeZone, posted: [PostedTraining]) -> [TodaysWorkout] {
        let fromHealth = posted.filter { $0.workout != nil }
        var byHand = posted.filter { $0.workout == nil && $0.day == day }.sorted { $0.madeAt < $1.madeAt }
        return filter { LocalDay(at: $0.workout.endedAt.date, in: timeZone) == day }
            .sorted { $0.workout.startedAt < $1.workout.startedAt }
            .map { imported in
                if fromHealth.contains(where: { $0.covers(imported) }) {
                    return TodaysWorkout(imported: imported, isPosted: true)
                }
                let cover = byHand.firstIndex {
                    $0.activity == imported.activity && imported.workout.startedAt <= $0.madeAt
                }
                if let cover { byHand.remove(at: cover) }
                return TodaysWorkout(imported: imported, isPosted: cover != nil)
            }
            .sorted { $0.imported.workout.endedAt > $1.imported.workout.endedAt }
    }
}

extension [TodaysWorkout] {
    /// What the home's card offers: the newest neither posted nor put away from the card.
    public func newestToPost(skipping putAway: Set<WorkoutSource> = []) -> ImportedWorkout? {
        first { !$0.isPosted && !putAway.contains($0.imported.id) }?.imported
    }
}

/// How many hours back Health is read for today: a whole day, from any time zone.
public let healthLookBackHours = 36.0
