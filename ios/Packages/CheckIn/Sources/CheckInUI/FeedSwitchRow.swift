#if os(iOS)
import DesignSystem
import DesignSystemUI
import SwiftUI

/// 发布到动态, pinned under 发动态 and the 请假条 page: a switch for whether the post goes in the
/// squad's 动态. It starts on and nothing is remembered. Off only records it: it counts for the squad
/// all the same, and the hint under the switch says it stays out of 动态 (the product owner,
/// 2026-11-10). The page sets its side margins.
struct FeedSwitchRow: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.controlPlacement) private var placement
    @Binding var inFeed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            SwitchRow(Text(copy: "发布到动态", bundle: .module), isOn: $inFeed, showsDivider: false)
                .accessibilityIdentifier("compose.inFeed")
            // Posting is the default and the switch says it; only the record-only choice needs a word.
            if !inFeed {
                Text(copy: "只记录，不出现在动态里", bundle: .module)
                    .typeStyle(TypeRamp.footnote)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .accessibilityIdentifier("compose.inFeed.hint")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Space.xs)
        .modifier(FeedSwitchRowSurface(placement: placement))
    }
}
/// In a page's content, a hairline above the row; floating in 发动态's action bar, a glass
/// panel of its own, so the switch and its hint read over the caption scrolling under it.
private struct FeedSwitchRowSurface: ViewModifier {
    let placement: ControlPlacement

    func body(content: Content) -> some View {
        switch placement {
        case .inContent:
            content.background(alignment: .top) { Hairline() }
        case .floating:
            content
                .padding(.horizontal, Space.m)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Radius.ticket, style: .continuous))
        }
    }
}
#endif
