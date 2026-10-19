#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// A choice shown as a picture, such as a hairstyle on the person's own character: a square
/// on the quiet surface. Selected it takes the scene's wash, a signature border and the check
/// badge, like `ChoiceTile`. The picture says what it is only to the eye, so `label` names it
/// for VoiceOver. It shrinks while held.
public struct PictureTile<Picture: View>: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var taps = 0
    private let label: Text
    private let isSelected: Bool
    private let action: () -> Void
    private let picture: Picture

    /// How far the check badge sits in from the tile's top-right corner.
    private let badgeInset: Double = 6

    public init(
        _ label: Text, isSelected: Bool, action: @escaping () -> Void, @ViewBuilder picture: () -> Picture
    ) {
        self.label = label
        self.isSelected = isSelected
        self.action = action
        self.picture = picture()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
        Button {
            taps += 1
            action()
        } label: {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { picture }
                .background(Color(role: isSelected ? .signatureWash : .surface, in: theme))
                .clipShape(shape)
                .overlay {
                    if isSelected {
                        shape.strokeBorder(Color(role: .signature, in: theme), lineWidth: Sizing.selectionStroke)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        CheckBadge()
                            .padding(badgeInset)
                            .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                    }
                }
                .contentShape(shape)
        }
        .buttonStyle(PressableButtonStyle())
        .animation(.wildcard(Motion.snappy, reduceMotion: reduceMotion), value: isSelected)
        .sensoryFeedback(.selection, trigger: taps)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
#endif
