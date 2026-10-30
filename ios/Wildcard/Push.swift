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
}

/// The app delegate, for what only it receives: the APNs token and taps on notifications.
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// What a tapped notification does; the scene sets it.
    var opened: (OpenedNotification) -> Void = { _ in }
    private lazy var taps = NotificationTaps { [weak self] in self?.opened($0) }

    func application(
        _ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Set before launching ends, so a tap that launched the app is delivered.
        UNUserNotificationCenter.current().delegate = taps
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
