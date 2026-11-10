import Contracts
import Foundation
import HealthDomain
import Observation

/// Apple Health as the app's screens read it: whether it is connected, what the member shares by
/// default, and today's workouts with which are posted already. One for the app, which 今天, 打卡
/// and 设置 › Apple 健康 share.
@MainActor @Observable
public final class HealthConnection {
    public private(set) var isConnected = false
    /// What a new post from Health carries unless struck; kept on this phone.
    public var sharing: HealthSharing {
        didSet { keep(sharing) }
    }
    /// The workouts read last, newest first; `today(_:in:posted:)` picks today's.
    public private(set) var recent: [ImportedWorkout] = []
    /// The workouts put away from the home's card on this phone; the card offers the next one.
    public private(set) var putAway: Set<WorkoutSource>
    /// The birthday the member chose to give on their profile, which places a heart-rate
    /// chart's zones; nil without one. Never read from Health. Kept on this phone with the rest,
    /// so a post from the home screen widgets places them too.
    public var birthday: Birthday? {
        didSet {
            guard birthday != oldValue else { return }
            if let birthday {
                defaults.set(birthday.description, forKey: Self.birthdayKey)
            } else {
                defaults.removeObject(forKey: Self.birthdayKey)
            }
        }
    }

    /// `putAway` in the order put away, oldest first.
    @ObservationIgnored private var stored: [WorkoutSource]
    @ObservationIgnored private let library: any HealthLibrary
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date

    public init(library: any HealthLibrary, defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.library = library
        self.defaults = defaults
        self.now = now
        sharing =
            defaults.data(forKey: Self.sharingKey).flatMap { try? JSONDecoder().decode(HealthSharing.self, from: $0) }
            .flatMap { $0.version == 1 ? $0 : nil } ?? HealthSharing()
        stored =
            defaults.data(forKey: Self.putAwayKey).flatMap { try? JSONDecoder().decode(PutAway.self, from: $0) }
            .flatMap { $0.version == 1 ? $0.workouts : nil } ?? []
        putAway = Set(stored)
        birthday = defaults.string(forKey: Self.birthdayKey).flatMap { try? LocalDay($0) }.map(Birthday.init(sent:))
    }

    /// Takes `workout` off the home's card for good on this phone; it can still be posted from 打卡.
    public func putAway(_ workout: WorkoutSource) {
        guard !putAway.contains(workout) else { return }
        // A card offers today's workouts alone, so the newest few are plenty to keep.
        stored = Array((stored + [workout]).suffix(Self.putAwayLimit))
        putAway = Set(stored)
        if let data = try? JSONEncoder().encode(PutAway(version: 1, workouts: stored)) {
            defaults.set(data, forKey: Self.putAwayKey)
        }
    }

    public var isAvailable: Bool { library.isAvailable }

    /// Reads whether it is connected and, if so, the last day and a half of workouts.
    public func refresh() async {
        isConnected = await library.isConnected()
        guard isConnected else {
            recent = []
            return
        }
        let end = now()
        recent = await library.workouts(endingFrom: end.addingTimeInterval(-healthLookBackHours * 3600), to: end)
    }

    /// Reads again each time Health saves or deletes a workout, until the caller's task is
    /// cancelled: 今天 follows it while on screen, so a workout that ends with the app open shows
    /// on its card in seconds instead of on the next return to the app. Returns at once while
    /// Health isn't connected.
    public func followChanges() async {
        guard await library.isConnected() else { return }
        for await _ in library.workoutChanges() {
            await refresh()
        }
    }

    /// 连接: asks the system once, then reads.
    public func connect() async {
        _ = await library.connect()
        await refresh()
    }

    /// Today's workouts for the member's `day`, newest first, each marked posted when `posted`
    /// holds it, with its heart-rate zones placed when the member gave their birthday.
    public func today(_ day: LocalDay, in timeZone: TimeZone, posted: Set<WorkoutSource>) -> [TodaysWorkout] {
        recent.map { $0.withZones(birthday: birthday, in: timeZone) }.today(day, in: timeZone, posted: posted)
    }

    /// Moves what this phone kept about Health (connected, what a post shares, what was put away
    /// from 今天's card) from `old` to `shared`, once, so the home screen widgets read the same:
    /// builds before the widgets kept it in the app's own defaults. Leaves `shared` as it is
    /// once it holds any of it.
    public static func share(from old: UserDefaults, to shared: UserDefaults) {
        let keys = [HealthKeys.connected, sharingKey, putAwayKey]
        guard keys.allSatisfy({ shared.object(forKey: $0) == nil }) else { return }
        for key in keys {
            if let value = old.object(forKey: key) { shared.set(value, forKey: key) }
        }
    }

    private func keep(_ sharing: HealthSharing) {
        if let data = try? JSONEncoder().encode(sharing) { defaults.set(data, forKey: Self.sharingKey) }
    }

    private static let sharingKey = "health.sharing"
    private static let putAwayKey = "health.putAway"
    private static let birthdayKey = "health.birthday"
    private static let putAwayLimit = 50

    /// What `putAway` keeps on the phone.
    private struct PutAway: Codable {
        let version: Int
        let workouts: [WorkoutSource]
    }
}

/// Where HealthKit's connection is kept on the phone, which `HealthConnection.share(from:to:)`
/// moves too.
enum HealthKeys {
    static let connected = "health.connected"
}
