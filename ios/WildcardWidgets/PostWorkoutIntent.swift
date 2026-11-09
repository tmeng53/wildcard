import AppIntents
import CheckInDomain
import Contracts
import Foundation
import HealthDomain
import HealthUI
import HomeWidgetDomain

/// 打卡 in a widget's capsule: posts the workout Health synced as a 训练 to my squad without
/// opening the app, as `WidgetBoard.checkIn(posting:…)` builds it: the numbers and the map and
/// chart 设置 › Apple 健康 shares, no photos. It asks to unlock first, since Health reads nothing
/// on a locked phone. It goes straight to the server, not through the app's outbox: one that
/// fails leaves the capsule for another tap, and if the app has the same workout waiting offline,
/// the server takes whichever lands first (a workout once a member). WidgetKit reads the widgets
/// again once it returns, so the capsule gives way to 今天练了.
struct PostWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "打卡"
    static let isDiscoverable = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    /// Health's id for the workout (`WorkoutSource.id`).
    @Parameter(title: "运动") var workout: String

    init() {}

    init(workout: WorkoutSource) {
        self.workout = workout.id
    }

    func perform() async throws -> some IntentResult {
        guard case .signedIn(let session) = await WidgetSession.open() else { return .result() }
        let backend = session.backend
        guard let home = try? await backend.home() else { return .result() }
        let health = await HealthRead.now(.full)
        let now = Date()
        let board = WidgetBoard(
            home: home, day: LocalDay(at: now, in: home.timeZone),
            // The chart's zones placed for my birthday, as the app places them.
            health: health.workouts.map { $0.withZones(birthday: health.birthday, in: home.timeZone) },
            putAway: health.putAway)
        guard
            let checkIn = board.checkIn(
                posting: workout, from: home, sharing: health.sharing, id: CheckInID(UUID()), at: Timestamp(now))
        else { return .result() }
        _ = try? await backend.save(checkIn)
        return .result()
    }
}
