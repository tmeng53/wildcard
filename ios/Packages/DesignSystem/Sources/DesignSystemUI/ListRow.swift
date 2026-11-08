#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// A 52-point row that opens something (性格 · 淡人 ›): an icon, the title, its current value in
/// muted ink and a chevron. A plain menu (设置) leaves out the icon. Rows in a
/// list are separated by a hairline under the text, so pass `showsDivider: false` on the last one.
public struct ListRow: View {
    @Environment(\.sceneTheme) private var theme
    private let title: Text
    private let systemImage: String?
    private let value: Text?
    private let showsDivider: Bool
    private let showsChevron: Bool
    private let action: (() -> Void)?

    public init(
        _ title: Text, systemImage: String? = nil, value: Text? = nil, showsDivider: Bool = true,
        showsChevron: Bool = true, action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.value = value
        self.showsDivider = showsDivider
        self.showsChevron = showsChevron
        self.action = action
    }

    /// A row that only shows its value, for someone who can't change it: no chevron, no tap.
    public init(_ title: Text, systemImage: String? = nil, value: Text, showsDivider: Bool = true) {
        self.title = title
        self.systemImage = systemImage
        self.value = value
        self.showsDivider = showsDivider
        self.showsChevron = false
        self.action = nil
    }

    public var body: some View {
        if let action {
            Button(action: action) { shell }
                .buttonStyle(.plain)
        } else {
            shell.accessibilityElement(children: .combine)
        }
    }

    private var shell: some View {
        RowShell(title: title, systemImage: systemImage, showsDivider: showsDivider) {
            if let value {
                value
                    .typeStyle(TypeRamp.footnote)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .lineLimit(1)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: Sizing.smallIcon - 2, weight: .semibold))
                    .foregroundStyle(Color(role: .fgSubtle, in: theme))
                    .accessibilityHidden(true)
            }
        }
    }
}

/// The 52-point list row both `ListRow` and `SwitchRow` are drawn in: an optional icon, the title,
/// what goes on the trailing side, and a hairline under it. The whole row takes the tap.
struct RowShell<Trailing: View>: View {
    @Environment(\.sceneTheme) private var theme
    let title: Text
    let systemImage: String?
    let showsDivider: Bool
    /// A line under the title saying more, in muted ink; nil for none.
    var detail: Text?
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: Space.s) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: Sizing.smallIcon + 2))
                    .frame(width: Sizing.icon)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: Space.xxs / 2) {
                title
                    .typeStyle(TypeRamp.body)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                if let detail {
                    detail
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.vertical, detail == nil ? 0 : Space.s)
        .frame(minHeight: Sizing.pickRow)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Hairline()
            }
        }
        .contentShape(Rectangle())
    }
}
#endif
