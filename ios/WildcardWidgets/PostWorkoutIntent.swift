import AppIntents
import CheckInDomain
import Contracts
import Foundation
import HomeWidgetDomain

/// 打卡 in a widget's capsule: posts the workout Health synced as a 训练 to my squad without
/// opening the app, as 今天's card would with nothing added, so no photos and no map or chart
/// (their tiles are drawn in the app), and the numbers 设置 › Apple 健康 shares. It posts only
/// while the board still offers that workout, so a second tap, or one after the app posted it,
/// does nothing; the server takes a workout once a member anyway. WidgetKit reads the widgets
/// again once it returns, so the capsule gives way to 今天练了.
struct PostWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "打卡"
    static let isDiscoverable = false

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
        let health = await HealthRead.now()
        let now = Date()
        let board = WidgetBoard(
            home: home, day: LocalDay(at: now, in: home.timeZone), health: health.workouts, putAway: health.putAway)
        guard let offered = board.workout, offered.id.id == workout, let activity = offered.activity,
            let audience = try? Audience([home.squad.id])
        else { return .result() }
        let training = Training(
            activity: activity, minutes: offered.minutes,
            workout: offered.workout.posting(struck: health.sharing.struck, positions: [:]))
        let checkIn = CheckIn(
            id: CheckInID(UUID()), member: home.member, day: board.day, createdAt: Timestamp(now),
            audience: audience, entry: .trained(training))
        _ = try? await backend.save(checkIn)
        return .result()
    }
}
