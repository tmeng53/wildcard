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

    #if DEBUG
    /// Shows the payload `-uitest-push` passed (if any) as iOS would, from the app's own String
    /// Catalog: its `loc-key` and `loc-args`, category and thread, with the payload as `userInfo` so
    /// a tap reaches the app as a pushed one does. The simulator can't take a push from APNs here,
    /// so the UI tests deliver the server's samples this way. Always as a banner, which a test can
    /// tap; a passive push (the daily one) goes only to Notification Center on a phone, which the
    /// server's own tests check.
    static func deliverLaunchSample() async {
        let center = UNUserNotificationCenter.current()
        guard let payload = LaunchOptions.pushSample,
            (try? await center.requestAuthorization(options: [.alert, .sound])) == true,
            let aps = payload["aps"] as? [String: Any],
            let alert = aps["alert"] as? [String: Any],
            let key = alert["loc-key"] as? String
        else { return }
        let content = UNMutableNotificationContent()
        let format = Bundle.main.localizedString(forKey: key, value: nil, table: nil)
        content.body = String(format: format, arguments: alert["loc-args"] as? [String] ?? [])
        content.categoryIdentifier = aps["category"] as? String ?? ""
        content.threadIdentifier = aps["thread-id"] as? String ?? ""
        content.userInfo = payload
        let soon = UNTimeIntervalNotificationTrigger(timeInterval: 8, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: key, content: content, trigger: soon))
    }
    #endif
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
        #if DEBUG
        Task { await Push.deliverLaunchSample() }
        #endif
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
