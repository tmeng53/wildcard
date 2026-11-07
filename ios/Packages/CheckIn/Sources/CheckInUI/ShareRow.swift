#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import SwiftUI

/// 分享到, pinned under 发动态 and the 请假条 page: a switch for whether the member's squad sees
/// the post. It starts on and nothing is remembered (the product owner, 2026-10-31). Off keeps the
/// post to the member, in 我的动态 only, and says so under the switch. The page sets its side margins.
struct ShareRow: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.controlPlacement) private var placement
    let squad: Squad
    @Binding var isShared: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            SwitchRow(Text("分享到 \(squad.name)", bundle: .module), isOn: $isShared, showsDivider: false)
                .accessibilityIdentifier("compose.share.\(squad.id)")
            // Sharing is the default and the switch says it; only the private choice needs a word.
            if !isShared {
                Text("仅自己可见，只在「我的动态」里", bundle: .module)
                    .typeStyle(TypeRamp.footnote)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .accessibilityIdentifier("compose.share.hint")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Space.xs)
        .modifier(ShareRowSurface(placement: placement))
    }
}
/// In a page's content, a hairline above the row; floating in 发动态's action bar, a glass
/// panel of its own, so the switch and its hint read over the caption scrolling under it.
private struct ShareRowSurface: ViewModifier {
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
