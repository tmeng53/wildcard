#if os(iOS)
import DesignSystem
import DesignSystemUI
import SwiftUI

/// 「未发动态」: on a check-in only recorded (发布到动态 off), in words, wherever its author sees it
/// (its own page, 我的动态's tiles), so they know their squad's 动态 doesn't show it.
public struct UnpostedTag: View {
    private let showsIcon: Bool

    /// `showsIcon` adds the icon before the words where there is room: a tile has none.
    public init(showsIcon: Bool = true) {
        self.showsIcon = showsIcon
    }

    public var body: some View {
        Tag(
            Text(copy: "未发动态", bundle: .module), systemImage: showsIcon ? "eye.slash" : nil, style: .rest,
            size: .small
        )
        // Smaller rather than cut off where text is large: a tile is about 93 points wide.
        .minimumScaleFactor(0.5)
        .accessibilityIdentifier("post.unposted")
    }
}
#endif
