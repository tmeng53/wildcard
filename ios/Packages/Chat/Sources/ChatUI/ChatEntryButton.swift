#if os(iOS)
import ChatDomain
import DesignSystem
import DesignSystemUI
import SwiftUI

/// The chat's entry, beside 打卡 on 今天: a glass round button in the scene's colour with the
/// unread count on its corner.
public struct ChatEntryButton: View {
    private let badge: ChatBadge
    private let open: () -> Void

    public init(badge: ChatBadge, open: @escaping () -> Void) {
        self.badge = badge
        self.open = open
    }

    public var body: some View {
        GlassRoundButton(
            Text("群聊", bundle: .module), systemImage: "bubble.left.and.bubble.right.fill",
            count: badge.unread.count, action: open
        )
        .task { await badge.refresh() }
        .accessibilityIdentifier("home.chat")
    }
}
#endif
