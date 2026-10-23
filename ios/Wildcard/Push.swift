import Backend
import DailyPushDomain
import DailyPushUI
import NotificationsDomain
import NotificationsUI
import UIKit
import UserNotifications

/// Push notifications for the whole app. iOS hands the device token and taps on a notification
/// to the app delegate, so the registration lives as long as the app does.
enum Push {
    static let registration = PushRegistration(system: SystemPush(), environment: .current)

    /// Pause after a post before the permission prompt, so the cheer plays out first.
    static let promptDelay = Duration.seconds(1.5)

    /// Where the 6pm push's view asked to open the app: 动态, 打卡, or nil for a plain tap.
    static func takeDestination() -> PushDestination? {
        AppGroup.defaults.map(PushDestinations.init).flatMap { $0.take(at: Date()) }
    }
}

/// The app delegate, for what only it receives: the APNs token and taps on notifications.
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// What a tapped notification does once the tabs are up; the scene sets it.
    var opened: () -> Void = {}
    /// Where the 6pm push's view asked to go, kept until the tabs take it: a tap that launched
    /// the app comes before they are there.
    private var destination: PushDestination?
    private lazy var taps = NotificationTaps { [weak self] in
        self?.destination = Push.takeDestination()
        self?.opened()
    }

    /// Where the last tapped notification asked to go, once.
    func takeDestination() -> PushDestination? {
        defer { destination = nil }
        return destination
    }

    func application(
        _ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Set before launching ends, so a tap that launched the app is delivered.
        UNUserNotificationCenter.current().delegate = taps
        // The 6pm push opens into today's check-ins (its content extension, by this category).
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: "dailyProgress", actions: [], intentIdentifiers: [])
        ])
        Task { await Push.registration.launched() }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
        let token = DeviceToken(token)
        // A registration that fails is made again on the next launch, when iOS hands it over again.
        Task { try? await Push.registration.received(token) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        // No token (no network, or a build without the push entitlement): the next launch asks again.
    }
}
