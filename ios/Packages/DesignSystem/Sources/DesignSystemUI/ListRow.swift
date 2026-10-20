#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// A 52-point row that opens something (性格 · 淡人 ›): an icon, the title, its current value in
/// muted ink and a chevron. Rows in a list are separated by a hairline under the text, so pass
/// `showsDivider: false` on the last one.
public struct ListRow: View {
    @Environment(\.sceneTheme) private var theme
    private let title: Text
    private let systemImage: String
    private let value: Text?
    private let showsDivider: Bool
    private let action: () -> Void

    public init(
        _ title: Text, systemImage: String, value: Text? = nil, showsDivider: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.value = value
        self.showsDivider = showsDivider
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s) {
                Image(systemName: systemImage)
                    .font(.system(size: Sizing.smallIcon + 2))
                    .frame(width: Sizing.icon)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .accessibilityHidden(true)
                title
                    .typeStyle(TypeRamp.body)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let value {
                    value
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                        .lineLimit(1)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: Sizing.smallIcon - 2, weight: .semibold))
                    .foregroundStyle(Color(role: .fgSubtle, in: theme))
                    .accessibilityHidden(true)
            }
            .frame(minHeight: Sizing.pickRow)
            .overlay(alignment: .bottom) {
                if showsDivider {
                    Rectangle()
                        .fill(Color(role: .borderDefault, in: theme))
                        .frame(height: Sizing.hairline)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
#endif
