#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// A compact choice: a small icon and a label in a capsule, for a row of recent or picked
/// choices. Plain it is a quiet white capsule; selected it takes the scene's wash with a
/// signature border. Removable pills end in a cross and remove themselves when tapped.
public struct ChoicePill: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var taps = 0
    private let title: Text
    private let systemImage: String
    private let isSelected: Bool
    private let isRemovable: Bool
    private let action: () -> Void

    /// The cross on a removable pill, smaller than the icon.
    private let removeGlyph: Double = 11

    public init(
        _ title: Text, systemImage: String, isSelected: Bool, isRemovable: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.isRemovable = isRemovable
        self.action = action
    }

    public var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            HStack(spacing: Space.xxs + Space.xxs / 2) {
                Image(systemName: systemImage)
                    .font(.system(size: Sizing.pillGlyph, weight: .medium))
                    .accessibilityHidden(true)
                title
                    .typeStyle(TypeRamp.callout)
                    .lineLimit(1)
                    .fixedSize()
                if isRemovable {
                    Image(systemName: "xmark")
                        .font(.system(size: removeGlyph, weight: .semibold))
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(Color(role: isSelected ? .signatureText : .textPrimary, in: theme))
            .padding(.leading, Space.xs + Space.xxs / 2)
            .padding(.trailing, isRemovable ? Space.xs + Space.xxs / 2 : Space.s)
            .frame(height: Sizing.pillHeight)
            .background(Color(role: isSelected ? .signatureWash : .canvas, in: theme), in: Capsule())
            .overlay {
                if isSelected {
                    Capsule().strokeBorder(Color(role: .signature, in: theme), lineWidth: Sizing.selectionStroke)
                }
            }
            // Draws 36 points tall but answers taps across the full 44.
            .padding(.vertical, (Sizing.minimumTapTarget - Sizing.pillHeight) / 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .animation(.wildcard(Motion.snappy, reduceMotion: reduceMotion), value: isSelected)
        .sensoryFeedback(.selection, trigger: taps)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isRemovable ? Text("移除这一项", bundle: .module) : Text(verbatim: ""))
    }
}
#endif
