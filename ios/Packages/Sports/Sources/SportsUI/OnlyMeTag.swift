#if os(iOS)
import DesignSystem
import DesignSystemUI
import SwiftUI

/// 「仅自己可见」: on a post shared to no squad, in words, wherever its author sees it (动态's card,
/// its own page, 我的动态's tiles), so nobody takes it for one their squad sees.
public struct OnlyMeTag: View {
    private let showsIcon: Bool

    /// `showsIcon` adds the lock before the words where there is room: a tile has none.
    public init(showsIcon: Bool = true) {
        self.showsIcon = showsIcon
    }

    public var body: some View {
        Tag(
            Text(copy: "仅自己可见", bundle: .module), systemImage: showsIcon ? "lock.fill" : nil, style: .rest,
            size: .small
        )
        // Smaller rather than cut off where text is large: a tile is about 93 points wide.
        .minimumScaleFactor(0.5)
        .accessibilityIdentifier("post.onlyMe")
    }
}
#endif
