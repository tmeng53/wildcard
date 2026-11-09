import AccountDomain
import AccountUI
import Backend
import Contracts
import DailyPushDomain
import DailyPushUI
import DesignSystem
import DesignSystemUI
import HealthDomain
import HealthUI
import SportsUI
import SwiftUI
import UIKit
import UserNotifications
import UserNotificationsUI

/// The 6pm push, long-pressed: today's check-ins to react to, drawn by `DailyPushView` from the
/// push itself and the squad's looks the app kept. Nothing loads when it opens; reacting is the
/// only call it makes, signed in with the app's shared session. A new workout's reminder,
/// long-pressed: the workout to post with one tap (`QuickPostView`), from the post it carries.
final class NotificationViewController: UIViewController, UNNotificationContentExtension {
    private var hosting: UIHostingController<AnyView>?
    /// The reminder's card, which its 写一句再发 posts from.
    private var quickPost: QuickPostModel?

    func didReceive(_ notification: UNNotification) {
        // The language the member picked in the app, before anything is looked up or drawn.
        AppLanguage.adopt(from: AppGroup.defaults, folder: AppGroup.directory)
        let content = notification.request.content
        // Sport names, from the list this build ships with: the app's newer copy is its own.
        SportList.shared.show(CatalogClient.bundled.sports)
        if content.categoryIdentifier == WorkoutReminderCenter.category {
            showQuickPost(content)
            return
        }
        guard let event = Self.event(content.userInfo), let push = try? DailyPush(event: event) else {
            // A push this build can't read: its words, as the banner shows them.
            show(AnyView(PlainPush(title: content.title, text: content.body)))
            return
        }
        let model = DailyPushModel(
            store: DailyPushStore(push: push, sender: Self.sender(for: push.viewer), now: { Date() }),
            arrived: notification.date,
            looks: AppGroup.directory.map(SharedSquad.init)?.looks() ?? [:]
        ) { [weak self] destination in
            self?.open(destination)
        }
        show(AnyView(DailyPushView(model: model)))
    }

    /// A new workout's reminder: its post with one tap, or its words when this build can't read it.
    private func showQuickPost(_ content: UNNotificationContent) {
        guard let text = content.userInfo[WorkoutReminderCenter.postKey] as? String,
            let post = try? JSONDecoder().decode(QuickPost.self, from: Data(text.utf8)), post.version == 1
        else {
            show(AnyView(PlainPush(title: content.title, text: content.body)))
            return
        }
        let model = QuickPostModel(post: post, poster: Self.poster(for: post.member)) { [weak self] in
            // A tap's own place: the compose page with the workout picked.
            self?.extensionContext?.performNotificationDefaultAction()
        }
        quickPost = model
        show(AnyView(QuickPostView(model: model)))
    }

    /// The reminder's 写一句再发: posted from the card with the line typed, which stays open to
    /// show what became of it. Any other action is the app's.
    func didReceive(
        _ response: UNNotificationResponse,
        completionHandler completion: @escaping (UNNotificationContentExtensionResponseOption) -> Void
    ) {
        guard response.actionIdentifier == WorkoutReminderCenter.captionAction,
            let typed = response as? UNTextInputNotificationResponse, let model = quickPost, model.canPost
        else {
            completion(.dismissAndForwardAction)
            return
        }
        let caption = typed.userText
        Task {
            await model.send(caption: caption)
            completion(.doNotDismiss)
        }
    }

    /// Opens the app where the member asked: the app takes the place on launch.
    private func open(_ destination: PushDestination) {
        AppGroup.defaults.map(PushDestinations.init)?.leave(destination, at: Date())
        extensionContext?.performNotificationDefaultAction()
    }

    private func show(_ content: AnyView) {
        hosting?.view.removeFromSuperview()
        hosting?.removeFromParent()
        let hosting = UIHostingController(rootView: AnyView(content.environment(\.locale, AppLanguage.current.locale)))
        hosting.sizingOptions = .preferredContentSize
        hosting.view.backgroundColor = .clear
        // The language it speaks, for UI tests to tell it from the system's own words.
        hosting.view.accessibilityIdentifier = "pushReact.\(AppLanguage.current.rawValue)"
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

    /// Reacting through our API, as the member signed in on the app, and only while that is the
    /// member the push is for. A build that names no backend (Debug) can't send.
    private static func sender(for member: MemberID) -> any ReactionSender {
        guard let api = api(for: member) else { return Unsent() }
        return APIReactionSender(api: api)
    }

    /// Posting a reminder's workout through our API, as `sender`, kept for the app to send when
    /// it can't go out from here. A build without a backend (Debug) can't post from here.
    private static func poster(for member: MemberID) -> any QuickPosting {
        guard let directory = AppGroup.directory, let api = api(for: member) else { return Unposted() }
        return APIQuickPoster(api: api, handoff: QuickPostHandoff(directory: directory))
    }

    /// Our API as `member`, signed in with the app's shared session; nil without a backend.
    private static func api(for member: MemberID) -> WildcardAPI? {
        guard let address = BackendAddress(info: Bundle.main.infoDictionary ?? [:]) else { return nil }
        let account = AccountSession(
            provider: SupabaseAuth(url: address.authURL, publishableKey: address.authPublishableKey),
            store: KeychainSessionStore(accessGroup: AppGroup.id), now: { Date() })
        return WildcardAPI(
            url: address.apiURL, account: account, member: member, language: { AppLanguage.current.rawValue })
    }
}

/// No backend to send to: every reaction is put back.
private struct Unsent: ReactionSender {
    func setReaction(_ emoji: Emoji?, on checkIn: CheckInID) async throws(DailyPushError) {
        throw .notSent
    }
}

/// No backend or app group to post through: the post can't go out from here.
private struct Unposted: QuickPosting {
    func post(_ post: QuickPost, struck: Set<WorkoutCell>, caption: String) async -> QuickPostOutcome { .refused }
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
        // Only this view has it, so a UI test can tell the extension drew from the system's text.
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pushReact.plain")
    }
}
