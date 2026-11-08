#if os(iOS)
import Contracts
import NotificationsDomain
import SwiftUI

extension View {
    /// The bell hears each notice as it is told while the app is in front: the stream is let go
    /// in the background and opened again, with the newest page read again, on the way back.
    /// After the server ends it, or it fails, it is opened again after `NoticeInbox.follow`'s wait.
    /// `told` hears each newest notice, for a screen showing what it is about.
    public func followsNotices(_ inbox: NoticeInbox, told: @escaping (Notice) -> Void = { _ in }) -> some View {
        modifier(FollowsNotices(inbox: inbox, told: told))
    }
}

private struct FollowsNotices: ViewModifier {
    let inbox: NoticeInbox
    /// Each newest notice as it comes, for a screen showing what it is about.
    let told: (Notice) -> Void
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content.task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await inbox.follow { try? await Task.sleep(for: $0) }
        }
        .onChange(of: inbox.notices.first?.id) {
            if let newest = inbox.notices.first { told(newest) }
        }
    }
}
#endif
