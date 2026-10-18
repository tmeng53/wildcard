#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// One choice in a three-column grid: an icon over a label. Plain it is a quiet white tile
/// with no shadow or rim; selected it takes the scene's wash, a signature border and a check
/// badge that springs in. It shrinks while held; with Reduce Motion on, only its state changes.
public struct ChoiceTile: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var taps = 0
    private let title: Text
    private let systemImage: String
    private let isSelected: Bool
    private let action: () -> Void

    /// How far the check badge sits in from the tile's top-right corner.
    private let badgeInset: Double = 7

    public init(_ title: Text, systemImage: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
        Button {
            taps += 1
            action()
        } label: {
            VStack(spacing: Space.xs) {
                Image(systemName: systemImage)
                    .font(.system(size: Sizing.tileGlyph, weight: .regular))
                    .frame(height: Sizing.tileGlyph)
                    .accessibilityHidden(true)
                title
                    .typeStyle(TypeRamp.tileLabel)
                    .lineLimit(1)
            }
            .foregroundStyle(Color(role: isSelected ? .signatureText : .textPrimary, in: theme))
            .padding(.horizontal, Space.xs)
            .padding(.vertical, Space.s)
            .frame(maxWidth: .infinity, minHeight: Sizing.tileHeight)
            .background(Color(role: isSelected ? .signatureWash : .canvas, in: theme), in: shape)
            .overlay {
                if isSelected {
                    shape.strokeBorder(Color(role: .signature, in: theme), lineWidth: Sizing.selectionStroke)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    CheckBadge()
                        .padding(badgeInset)
                        .transition(badgeTransition)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(PressableButtonStyle())
        .animation(.wildcard(Motion.snappy, reduceMotion: reduceMotion), value: isSelected)
        .sensoryFeedback(.selection, trigger: taps)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var badgeTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return AnyTransition.scale.combined(with: .opacity).animation(.wildcard(Motion.panel))
    }
}

/// A small solid signature disc with a check, for the corner of a selected choice.
struct CheckBadge: View {
    @Environment(\.sceneTheme) private var theme
    private let glyph: Double = 10

    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: glyph, weight: .heavy))
            .foregroundStyle(Color(role: .onSignature, in: theme))
            .frame(width: Sizing.checkBadge, height: Sizing.checkBadge)
            .background(Color(role: .signature, in: theme), in: Circle())
            .accessibilityHidden(true)
    }
}
#endif
