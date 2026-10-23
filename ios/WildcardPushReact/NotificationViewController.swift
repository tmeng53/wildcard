import AccountDomain
import AccountUI
import Backend
import Contracts
import DailyPushDomain
import DailyPushUI
import DesignSystem
import DesignSystemUI
import SwiftUI
import UIKit
import UserNotifications
import UserNotificationsUI

/// The 6pm push, long-pressed: today's check-ins to react to, drawn by `DailyPushView` from the
/// push itself and the squad's looks the app kept. Nothing loads when it opens; reacting is the
/// only call it makes, signed in with the app's shared session.
final class NotificationViewController: UIViewController, UNNotificationContentExtension {
    private var hosting: UIHostingController<AnyView>?

    func didReceive(_ notification: UNNotification) {
        let content = notification.request.content
        guard let event = Self.event(content.userInfo), let push = try? DailyPush(event: event) else {
            // A push this build can't read: its words, as the banner shows them.
            show(AnyView(PlainPush(title: content.title, text: content.body)))
            return
        }
        let model = DailyPushModel(
            store: DailyPushStore(push: push, sender: Self.sender(), now: { Date() }), arrived: notification.date,
            looks: AppGroup.directory.map(SharedSquad.init)?.looks() ?? [:]
        ) { [weak self] destination in
            self?.open(destination)
        }
        show(AnyView(DailyPushView(model: model)))
    }

    /// Opens the app where the member asked: the app takes the place on launch.
    private func open(_ destination: PushDestination) {
        AppGroup.defaults.map(PushDestinations.init)?.leave(destination, at: Date())
        extensionContext?.performNotificationDefaultAction()
    }

    private func show(_ view: AnyView) {
        hosting?.view.removeFromSuperview()
        hosting?.removeFromParent()
        let hosting = UIHostingController(rootView: view)
        hosting.sizingOptions = .preferredContentSize
        hosting.view.backgroundColor = .clear
        addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hosting.didMove(toParent: self)
        self.hosting = hosting
    }

    override func preferredContentSizeDidChange(forChildContentContainer container: any UIContentContainer) {
        super.preferredContentSizeDidChange(forChildContentContainer: container)
        preferredContentSize = CGSize(width: view.bounds.width, height: container.preferredContentSize.height)
    }

    /// The push's `event`, which the API sends as a JSON object.
    private static func event(_ userInfo: [AnyHashable: Any]) -> Data? {
        guard let event = userInfo["event"], JSONSerialization.isValidJSONObject(event) else { return nil }
        return try? JSONSerialization.data(withJSONObject: event)
    }

    /// Reacting through our API, as the member signed in on the app. A build that names no
    /// backend (Debug) can't send.
    private static func sender() -> any ReactionSender {
        guard let address = BackendAddress(info: Bundle.main.infoDictionary ?? [:]) else { return Unsent() }
        let account = AccountSession(
            provider: SupabaseAuth(url: address.authURL, publishableKey: address.authPublishableKey),
            store: KeychainSessionStore(accessGroup: AppGroup.id), now: { Date() })
        return APIReactionSender(api: WildcardAPI(url: address.apiURL, account: account))
    }
}

/// No backend to send to: every reaction is put back.
private struct Unsent: ReactionSender {
    func setReaction(_ emoji: Emoji?, on checkIn: CheckInID) async throws(DailyPushError) {
        throw .notSent
    }
}

/// A push the view can't draw: its title and words.
private struct PlainPush: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            Text(verbatim: title).typeStyle(TypeRamp.headline)
            Text(verbatim: text).typeStyle(TypeRamp.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
}
