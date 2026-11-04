#if os(iOS)
import NotificationsDomain
import SwiftUI

extension View {
    /// The bell hears each notice as it is told while the app is in front: the stream is let go
    /// in the background and opened again, with the newest page read again, on the way back.
    /// After the server ends it, or it fails, it is opened again after `NoticeInbox.follow`'s wait.
    public func followsNotices(_ inbox: NoticeInbox) -> some View {
        modifier(FollowsNotices(inbox: inbox))
    }
}

private struct FollowsNotices: ViewModifier {
    let inbox: NoticeInbox
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content.task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await inbox.follow { try? await Task.sleep(for: $0) }
        }
    }
}
#endif
