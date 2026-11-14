#if os(iOS)
import DesignSystem
import DesignSystemUI
import NotificationsDomain
import SwiftUI

/// The bell at the top right of 动态 (the approved bell design): a round header button, with a
/// small graphite dot while a notice is newer than the newest the member has seen. No count and
/// no red: news, never a debt.
public struct NoticeBell: View {
    private let inbox: NoticeInbox
    private let open: () -> Void

    public init(inbox: NoticeInbox, open: @escaping () -> Void) {
        self.inbox = inbox
        self.open = open
    }

    public var body: some View {
        HeaderButton(label, systemImage: "bell", action: open)
            .newsDot(inbox.hasUnread)
            .accessibilityIdentifier("notices.bell")
            .accessibilityValue(inbox.hasUnread ? Text(copy: "有新通知", bundle: .module) : Text(verbatim: ""))
    }

    private var label: Text { Text(copy: "通知", bundle: .module) }
}
#endif
