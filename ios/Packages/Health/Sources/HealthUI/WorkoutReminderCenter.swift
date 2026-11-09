#if canImport(HealthKit) && os(iOS)
import Contracts
import DesignSystemUI
import Foundation
import HealthDomain
import SportsUI
import UserNotifications

/// Reminds the member of a new workout from Health (Tracy, 2026-11-08): when HealthKit wakes the
/// app for one, a local notification 「跑步 32 分钟 · 5.2 公里 / 要打卡吗？长按一键打卡」, once a
/// workout, for today's not yet posted (`WorkoutReminders`). It carries the workout's
/// `QuickPost`, which its long-press card (the push content extension's `newWorkout` view)
/// posts with one tap; a tap on it opens the compose page with the workout picked. Only while
/// 设置 › Apple 健康's 新运动提醒 is on and notifications are allowed.
public actor WorkoutReminderCenter {
    /// The notification's category, which the content extension draws.
    public static let category = "newWorkout"
    /// Where the `QuickPost` is in a reminder's `userInfo`, as JSON text.
    public static let postKey = "quickPost"
    /// The reminder's 写一句再发: the system's text field under the card, whose 发布 posts the
    /// workout with the line typed. Leaving it is the card's own 发布, with no words.
    public static let captionAction = "newWorkout.caption"

    /// The reminder's category, with its 写一句再发.
    @MainActor public static var notificationCategory: UNNotificationCategory {
        let bundle = Bundle.module.inAppLanguage
        let write = UNTextInputNotificationAction(
            identifier: captionAction, title: String(localized: "写一句再发", bundle: bundle),
            options: [], icon: UNNotificationActionIcon(systemImageName: "text.bubble"),
            textInputButtonTitle: String(localized: "发布", bundle: bundle),
            textInputPlaceholder: String(localized: "说点什么（可选）", bundle: bundle))
        return UNNotificationCategory(identifier: category, actions: [write], intentIdentifiers: [])
    }

    private let library: HealthKitLibrary
    private let defaults: UserDefaults
    private let context: @Sendable () -> PostingContext?
    private let sharing: @Sendable () -> HealthSharing
    private let now: @Sendable () -> Date
    private var isWatching = false

    /// - Parameters:
    ///   - context: who posts for which squad, as the home last loaded; nil before it did.
    ///   - sharing: what 设置 › Apple 健康 shares by default.
    public init(
        library: HealthKitLibrary, defaults: UserDefaults = .standard,
        context: @escaping @Sendable () -> PostingContext?, sharing: @escaping @Sendable () -> HealthSharing,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.library = library
        self.defaults = defaults
        self.context = context
        self.sharing = sharing
        self.now = now
    }

    /// Starts listening for new workouts: from launching, and again once Health is connected.
    public func start() async {
        guard !isWatching, await library.isConnected() else { return }
        isWatching = true
        library.watchWorkouts { [weak self] in await self?.check() }
    }

    /// Reminds of each new workout due one, and takes away reminders of workouts posted since.
    public func check() async {
        guard let context = context() else { return }
        Self.withdraw(context.posted.map(Self.identifier))
        guard HealthConnection.remindsOfWorkouts(in: defaults), await library.isConnected(), await Self.mayNotify()
        else { return }
        let moment = now()
        let workouts = await library.workouts(
            endingFrom: moment.addingTimeInterval(-healthLookBackHours * 3600), to: moment)
        let due = WorkoutReminders.due(workouts, context: context, reminded: reminded, now: moment)
        let day = LocalDay(at: moment, in: context.zone)
        for imported in due {
            remember(imported.id)
            await Self.remind(of: QuickPost(context: context, day: day, imported: imported, sharing: sharing()))
        }
    }

    // UserNotifications' objects stay in these, off the actor.

    private static func mayNotify() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional
    }

    private static func remind(of post: QuickPost) async {
        guard let content = content(for: post) else { return }
        let request = UNNotificationRequest(identifier: identifier(post.workout.source), content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    private static func withdraw(_ identifiers: [String]) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    #if DEBUG
    /// A sample run's reminder in `seconds`, for UI tests: the long-press card can't post it
    /// (Debug builds have no backend there).
    public static func remindOfSample(after seconds: Double) async {
        let end = Date().addingTimeInterval(-300)
        let run = ImportedWorkout(
            workout: Workout(
                source: WorkoutSource(provider: WorkoutSource.appleHealth, id: "sample-run"),
                startedAt: Timestamp(end.addingTimeInterval(-1920)), endedAt: Timestamp(end),
                summary: WorkoutSummary(durationSec: 1920, distanceM: 5200, paceSecPerKm: 369, avgHr: 148)),
            activity: .sport("run"))
        let context = PostingContext(
            member: MemberID(UUID()), squad: SquadID(UUID()), squadName: "周三不练腿俱乐部",
            timeZone: TimeZone.current.identifier, posted: [])
        let post = QuickPost(
            context: context, day: LocalDay(at: end, in: .current), imported: run, sharing: HealthSharing())
        guard let content = content(for: post) else { return }
        let soon = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: identifier(run.id), content: content, trigger: soon))
    }
    #endif

    /// The reminder's words, in the app's language, with the post it carries.
    static func content(for post: QuickPost) -> UNMutableNotificationContent? {
        guard let json = try? JSONEncoder().encode(post), let text = String(data: json, encoding: .utf8) else {
            return nil
        }
        let content = UNMutableNotificationContent()
        content.title = title(of: post.imported)
        content.body = String(localized: "要打卡吗？长按一键打卡", bundle: .module.inAppLanguage)
        content.categoryIdentifier = category
        content.threadIdentifier = category
        // `event` as a push's, which a tap reads (`OpenedNotification`).
        content.userInfo = [
            postKey: text, "event": ["provider": post.workout.source.provider, "workout": post.workout.source.id],
        ]
        return content
    }

    /// 「跑步 32 分钟 · 5.2 公里」: the sport, its minutes, and its distance when it has one.
    static func title(of imported: ImportedWorkout) -> String {
        let bundle = Bundle.module.inAppLanguage
        let sport = imported.activity?.localizedName ?? String(localized: "运动", bundle: bundle)
        guard let minutes = imported.minutes?.value else { return sport }
        guard let meters = imported.workout.summary.distanceM, meters >= 100 else {
            return String(localized: "\(sport) \(minutes) 分钟", bundle: bundle)
        }
        let kilometres = (meters / 1000).formatted(
            .number.precision(.fractionLength(0...1)).locale(AppLanguage.current.locale))
        return String(localized: "\(sport) \(minutes) 分钟 · \(kilometres) 公里", bundle: bundle)
    }

    static func identifier(_ workout: WorkoutSource) -> String {
        "\(category).\(workout.provider).\(workout.id)"
    }

    /// The workouts reminded of on this phone, newest last.
    private var reminded: Set<WorkoutSource> { Set(stored) }

    private var stored: [WorkoutSource] {
        defaults.data(forKey: Self.remindedKey).flatMap { try? JSONDecoder().decode(Reminded.self, from: $0) }
            .flatMap { $0.version == 1 ? $0.workouts : nil } ?? []
    }

    private func remember(_ workout: WorkoutSource) {
        let kept = Array((stored.filter { $0 != workout } + [workout]).suffix(WorkoutReminders.rememberedMax))
        if let data = try? JSONEncoder().encode(Reminded(version: 1, workouts: kept)) {
            defaults.set(data, forKey: Self.remindedKey)
        }
    }

    private static let remindedKey = "health.reminded"

    /// What `remember` keeps on the phone.
    private struct Reminded: Codable {
        let version: Int
        let workouts: [WorkoutSource]
    }
}
#endif
