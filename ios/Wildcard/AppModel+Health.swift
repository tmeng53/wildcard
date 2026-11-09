import Backend
import HealthUI

extension AppModel {
    /// HealthKit, one for the app.
    private nonisolated static let healthLibrary = HealthKitLibrary()

    /// Apple Health through HealthKit, one for the app: a member signing in again keeps it, and
    /// what it shares by default is this phone's.
    static let health = HealthConnection(library: healthLibrary)

    /// Reminders of new workouts from Health, which HealthKit wakes the app for, posting for the
    /// member and squad the home last loaded.
    nonisolated static let workoutReminders = WorkoutReminderCenter(
        library: healthLibrary, context: { AppGroup.directory.map(SharedPostingContext.init)?.load() },
        sharing: { HealthConnection.sharing(in: .standard) })

    /// Who posts for which squad, kept for a new workout's reminder and its long-press card.
    nonisolated static let posting = AppGroup.directory.map(SharedPostingContext.init)

    /// Posts made from a new workout's reminder that couldn't go out from there.
    private nonisolated static let quickPosts = AppGroup.directory.map(QuickPostHandoff.init)

    /// Sends what was posted from a new workout's reminder while it couldn't go out.
    func sendQuickPosts() async {
        guard case .tabs(let today, _, _, _, _, _) = screen, let quickPosts = Self.quickPosts else { return }
        await today.adoptQuickPosts { await quickPosts.takeAll() }
    }
}
