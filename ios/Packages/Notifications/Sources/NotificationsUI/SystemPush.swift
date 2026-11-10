#if os(iOS)
import NotificationsDomain
import UIKit
import UserNotifications

/// iOS's notification permission and APNs registration. The token comes back to the app
/// delegate's `didRegisterForRemoteNotificationsWithDeviceToken`.
public struct SystemPush: PushSystem {
    public init() {}

    public func authorization() async -> PushAuthorization {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .notDetermined: .notDetermined
        case .authorized, .provisional, .ephemeral: .allowed
        case .denied: .denied
        @unknown default: .denied
        }
    }

    public func requestAuthorization() async -> Bool {
        // Banners and sound, no badge: a number on the icon reads as a to-do list.
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    public func registerForRemoteNotifications() async {
        await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
    }
}

/// Shows a notification that arrives while the app is open, and tells the app when the member
/// taps one. iOS keeps its delegate weakly, so the app delegate holds this.
public final class NotificationTaps: NSObject, UNUserNotificationCenterDelegate, Sendable {
    private let arrived: @MainActor @Sendable (String) -> Bool
    private let opened: @MainActor @Sendable (OpenedNotification) -> Void

    /// - Parameters:
    ///   - arrived: a notification of a category arrived while the app is in front; true when
    ///     the app tells it in its own banner (the one that drops in over any page), so iOS shows
    ///     only it in Notification Center, false for iOS's banner.
    ///   - opened: the member tapped a notification, which opened the app.
    public init(
        arrived: @escaping @MainActor @Sendable (String) -> Bool,
        opened: @escaping @MainActor @Sendable (OpenedNotification) -> Void
    ) {
        (self.arrived, self.opened) = (arrived, opened)
    }

    // The completion-handler forms, not the async ones: iOS calls these through Objective-C, and
    // the async forms finish on a background thread, which UIKit refuses (a tap on a notification
    // crashed TestFlight build 82.1 this way). The parameters aren't Sendable, so only plain values
    // cross to the main actor.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let done = PresentationCompletion(call: completionHandler)
        let category = notification.request.content.categoryIdentifier
        Task { @MainActor [arrived] in
            done.call(arrived(category) ? [.list] : [.banner, .list, .sound])
        }
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else {
            completionHandler()
            return
        }
        let payload = response.notification.request.content
        let event = (payload.userInfo["event"] as? [String: Any] ?? [:]).compactMapValues { $0 as? String }
        let tapped = OpenedNotification(category: payload.categoryIdentifier, event: event)
        let done = MainThreadCompletion(completionHandler)
        Task { @MainActor [opened] in
            opened(tapped)
            done.call()
        }
    }
}

// iOS's completion handler, carried to the main actor and called there once.
private struct MainThreadCompletion: @unchecked Sendable {  // only called once, on the main actor
    let call: () -> Void

    init(_ call: @escaping () -> Void) {
        self.call = call
    }
}

// How iOS should show a notification that arrived in front, carried to the main actor likewise.
private struct PresentationCompletion: @unchecked Sendable {  // only called once, on the main actor
    let call: (UNNotificationPresentationOptions) -> Void
}
#endif
