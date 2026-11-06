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

    /// 连接: asks the system once, then reads.
    public func connect() async {
        _ = await library.connect()
        await refresh()
    }

    /// Today's workouts for the member's `day`, newest first, each marked posted when `posted`
    /// holds it.
    public func today(_ day: LocalDay, in timeZone: TimeZone, posted: Set<WorkoutSource>) -> [TodaysWorkout] {
        recent.today(day, in: timeZone, posted: posted)
    }

    private func keep(_ sharing: HealthSharing) {
        if let data = try? JSONEncoder().encode(sharing) { defaults.set(data, forKey: Self.sharingKey) }
    }

    private static let sharingKey = "health.sharing"
}
