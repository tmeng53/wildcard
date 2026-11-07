import Contracts
import Foundation

/// A workout as it comes from Health, before the member posts it: every number Health has for
/// its kind of sport, the route already trimmed, the heart rate thinned, and the sport of the
/// sports list it is (nil when the list has none like it).
public struct ImportedWorkout: Hashable, Sendable, Identifiable {
    /// Its numbers, series and route; no tile position yet: the compose page places the tile.
    public let workout: Workout
    public let activity: Activity?

    public init(workout: Workout, activity: Activity?) {
        self.workout = workout
        self.activity = activity
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
/// 「发到小队时默认带上」): all on until switched off. 时长 always goes. Kept on the phone, with a
/// `version` as stored JSON.
public struct HealthSharing: Hashable, Sendable, Codable {
    public var version = 1
    public var distance = true
    /// 配速 for a run or walk, 均速 for a ride.
    public var pace = true
    public var heartRate = true
    public var effort = true
    public var laps = true
    public var route = true

    public init() {}

    /// The cells a new post from Health starts with struck.
    public var struck: Set<WorkoutCell> {
        var cells: Set<WorkoutCell> = []
        if !distance { cells.insert(.distance) }
        if !pace { cells.formUnion([.pace, .speed]) }
        if !heartRate { cells.formUnion([.averageHeartRate, .maxHeartRate]) }
        if !effort { cells.insert(.effort) }
        if !laps { cells.insert(.laps) }
        return cells
    }

    /// Whether a new post from `workout` starts with its tile: the map follows 路线地图, a lap
    /// chart 趟数 and a heart-rate chart 心率.
    public func keepsTile(of workout: Workout) -> Bool {
        switch workout.tile {
        case .map: route
        case .chart: workout.series?.laps?.isEmpty == false ? laps : heartRate
        case nil: false
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
    /// Those that ended on the member's `day` (a day runs to 3am), newest first, each marked
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

/// How many hours back Health is read for today: a day with its 3am grace, from any time zone.
public let healthLookBackHours = 36.0
