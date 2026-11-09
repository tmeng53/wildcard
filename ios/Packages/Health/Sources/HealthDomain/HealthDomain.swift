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

    /// The workout with its heart-rate zones placed for a member born on `birthday`, as of the
    /// day it started; unchanged without a birthday or a heart-rate curve. Only the zones are
    /// posted, never the birthday or the resting heart rate.
    public func withZones(birthday: DateComponents?, calendar: Calendar) -> Workout {
        guard let series = workout.series, let curve = series.heartRate, let birthday,
            let born = calendar.date(from: birthday),
            let age = calendar.dateComponents([.year], from: born, to: workout.startedAt.date).year,
            let zones = HeartRateZones(age: age, restingBpm: restingBpm)
        else { return workout }
        return Workout(
            source: workout.source, startedAt: workout.startedAt, endedAt: workout.endedAt, summary: workout.summary,
            series: WorkoutSeries(heartRate: curve, laps: series.laps, zones: zones), route: workout.route,
            tilePosition: workout.tilePosition, chartPosition: workout.chartPosition)
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

extension [ImportedWorkout] {
    /// Those that ended on the member's `day`, newest first, each marked
    /// posted when `posted` holds it: a member posts each workout once.
    public func today(_ day: LocalDay, in timeZone: TimeZone, posted: Set<WorkoutSource>) -> [TodaysWorkout] {
        filter { LocalDay(at: $0.workout.endedAt.date, in: timeZone) == day }
            .sorted { $0.workout.endedAt > $1.workout.endedAt }
            .map { TodaysWorkout(imported: $0, isPosted: posted.contains($0.id)) }
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
