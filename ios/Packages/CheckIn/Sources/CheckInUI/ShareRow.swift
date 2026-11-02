#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import SwiftUI

/// 分享到, pinned under 发动态 and the 请假条 page: which of the member's squads see the post.
/// Every squad starts ticked and nothing is remembered (the product owner, 2026-10-31). One squad
/// is a switch; two or three are pills to pick from. None ticked keeps the post to the member,
/// in 我的动态 only. The page sets its side margins.
struct ShareRow: View {
    @Environment(\.sceneTheme) private var theme
    let squads: [Squad]
    @Binding var shared: Set<SquadID>

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            if let only = squads.first, squads.count == 1 {
                SwitchRow(Text("分享到 \(only.name)", bundle: .module), isOn: isShared(only), showsDivider: false)
                    .accessibilityIdentifier("compose.share.\(only.id)")
                hint(shared.isEmpty ? Text("仅自己可见，只在「我的动态」里", bundle: .module) : Text("小队成员都能看到", bundle: .module))
            } else {
                SectionLabel(Text("分享到", bundle: .module))
                FlowRow {
                    ForEach(squads, id: \.id) { squad in
                        PickPill(Text(verbatim: squad.name), look: .solid, isSelected: shared.contains(squad.id)) {
                            if shared.contains(squad.id) { shared.remove(squad.id) } else { shared.insert(squad.id) }
                        }
                        .accessibilityIdentifier("compose.share.\(squad.id)")
                    }
                }
                hint(
                    shared.isEmpty
                        ? Text("仅自己可见，只在「我的动态」里", bundle: .module) : Text("都不选就是仅自己可见", bundle: .module))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Space.xs)
        .background(alignment: .top) {
            Rectangle()
                .fill(Color(role: .borderDefault, in: theme))
                .frame(height: Sizing.hairline)
        }
    }

    private func hint(_ text: Text) -> some View {
        text
            .typeStyle(TypeRamp.footnote)
            .foregroundStyle(Color(role: .fgMuted, in: theme))
            .accessibilityIdentifier("compose.share.hint")
    }

    private func isShared(_ squad: Squad) -> Binding<Bool> {
        Binding {
            shared.contains(squad.id)
        } set: { isOn in
            if isOn { shared.insert(squad.id) } else { shared.remove(squad.id) }
        }
    }
}
#endif
