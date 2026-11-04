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

    /// The dot, and the ring of the button's own colour around it.
    private static let dot: Double = 8
    private static let dotRing: Double = 2

    public init(inbox: NoticeInbox, open: @escaping () -> Void) {
        self.inbox = inbox
        self.open = open
    }

    public var body: some View {
        HeaderButton(label, systemImage: "bell", action: open)
            .overlay(alignment: .topTrailing) {
                if inbox.hasUnread {
                    Circle()
                        .fill(Color(role: .bgBrand, in: .gym))
                        .frame(width: Self.dot, height: Self.dot)
                        .padding(Self.dotRing)
                        .background(Circle().fill(Color(role: .bgCanvas, in: .gym)))
                        .offset(x: -Self.dot / 2, y: Self.dot / 2)
                        .transition(.opacity)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityIdentifier("notices.bell")
            .accessibilityValue(inbox.hasUnread ? Text("有新通知", bundle: .module) : Text(verbatim: ""))
    }

    private var label: Text { Text("通知", bundle: .module) }
}
#endif
