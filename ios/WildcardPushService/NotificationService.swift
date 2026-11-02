import Backend
import DesignSystemUI
import Foundation
import NotificationsDomain
import UserNotifications

/// Every push, just before it shows: its words again, in the language the member picked in the
/// app. A push carries a String Catalog key, which iOS looks up in the phone's language; the app
/// opens in its own language whatever the phone's (`AppLanguage`), so this looks the key up in the
/// app's catalog in that language instead. A push it can't read shows as iOS wrote it.
final class NotificationService: UNNotificationServiceExtension {
    override func didReceive(
        _ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        AppLanguage.adopt(from: AppGroup.defaults)
        contentHandler(Self.inAppLanguage(request.content))
    }

    private static func inAppLanguage(_ content: UNNotificationContent) -> UNNotificationContent {
        guard let words = PushAlertWords(aps: content.userInfo["aps"] as? [String: Any]),
            let catalog = appBundle?.inAppLanguage
        else { return content }
        let line = catalog.localizedString(forKey: words.key, value: nil, table: nil)
        guard line != words.key, let rewritten = content.mutableCopy() as? UNMutableNotificationContent else {
            return content
        }
        rewritten.body = words.fill(line)
        return rewritten
    }

    /// The app this extension ships in (`Wildcard.app/PlugIns/WildcardPushService.appex`), whose
    /// catalog holds the push copy.
    private static var appBundle: Bundle? {
        Bundle(url: Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent())
    }
}
