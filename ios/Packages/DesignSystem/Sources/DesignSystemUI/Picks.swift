#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

// What I picked: a white shape with a hairline; picked, a 1.5-point accent border and a solid
// check. Never a thick colored block. Each pick shrinks while held and ticks once when tapped.

/// One choice as a 52-point row: an icon, the label and, once picked, a check. For a list or a
/// two-column grid (平时练什么？).
public struct PickRow: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var taps = 0
    private let title: Text
    private let systemImage: String?
    private let isSelected: Bool
    private let action: () -> Void

    public init(_ title: Text, systemImage: String? = nil, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.pick, style: .continuous)
        Button {
            taps += 1
            action()
        } label: {
            HStack(spacing: Space.s) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: Sizing.smallIcon + 2, weight: .regular))
                        .frame(width: Sizing.icon)
                        .accessibilityHidden(true)
                }
                title
                    .typeStyle(TypeRamp.pick)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isSelected {
                    CheckBadge()
                        .transition(badgeTransition)
                }
            }
            .foregroundStyle(Color(role: .fgDefault, in: theme))
            .padding(.horizontal, Space.s + 2)
            .frame(minHeight: Sizing.pickRow)
            .background(Color(role: .bgCanvas, in: theme), in: shape)
            .overlay { PickBorder(shape: shape, isSelected: isSelected) }
            .contentShape(shape)
        }
        .buttonStyle(PressableButtonStyle())
        .animation(.wildcard(Motion.change, reduceMotion: reduceMotion), value: isSelected)
        .sensoryFeedback(.selection, trigger: taps)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var badgeTransition: AnyTransition {
        reduceMotion ? .opacity : .scale.combined(with: .opacity)
    }
}

/// A compact choice: a capsule with a word and maybe an icon, for a wrapping row of more
/// choices (更多). Picked, it takes the accent border and a heavier word. Removable pills end in
/// a cross; the caller removes the pill in `action`.
public struct PickPill: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var taps = 0
    private let title: Text
    private let systemImage: String?
    private let isSelected: Bool
    private let isRemovable: Bool
    private let action: () -> Void

    /// The cross on a removable pill, smaller than the icon.
    private let removeGlyph: Double = 11

    public init(
        _ title: Text, systemImage: String? = nil, isSelected: Bool, isRemovable: Bool = false,
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
            HStack(spacing: Space.xs - 2) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: Sizing.smallIcon, weight: .medium))
                        .accessibilityHidden(true)
                }
                title
                    .typeStyle(isSelected ? TypeRamp.calloutEmphasis : TypeRamp.callout)
                    .lineLimit(1)
                    .fixedSize()
                if isRemovable {
                    Image(systemName: "xmark")
                        .font(.system(size: removeGlyph, weight: .semibold))
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(Color(role: .fgDefault, in: theme))
            .padding(.horizontal, Space.s + 2)
            // Grows with Dynamic Type instead of clipping the label.
            .frame(minHeight: Sizing.compactControl)
            .background(Color(role: .bgCanvas, in: theme), in: Capsule())
            .overlay { PickBorder(shape: Capsule(), isSelected: isSelected) }
            // Draws 36 points tall but answers taps across the full 44.
            .padding(.vertical, (Sizing.minimumTapTarget - Sizing.compactControl) / 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .animation(.wildcard(Motion.change, reduceMotion: reduceMotion), value: isSelected)
        .sensoryFeedback(.selection, trigger: taps)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isRemovable ? Text("移除这一项", bundle: .module) : Text(verbatim: ""))
    }
}

/// A choice shown as a picture, such as a hairstyle on the person's own character: a white
/// square with a hairline; picked, the accent border and the check in its corner. The picture
/// says what it is only to the eye, so `label` names it for VoiceOver.
public struct PickTile<Picture: View>: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var taps = 0
    private let label: Text
    private let isSelected: Bool
    private let action: () -> Void
    private let picture: Picture

    /// How far the check sits in from the tile's top-right corner.
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
        let shape = RoundedRectangle(cornerRadius: Radius.pick, style: .continuous)
        Button {
            taps += 1
            action()
        } label: {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { picture }
                .background(Color(role: .bgCanvas, in: theme))
                .clipShape(shape)
                .overlay { PickBorder(shape: shape, isSelected: isSelected) }
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
        .animation(.wildcard(Motion.change, reduceMotion: reduceMotion), value: isSelected)
        .sensoryFeedback(.selection, trigger: taps)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A hairline around an unpicked shape; the accent border around a picked one.
struct PickBorder<S: InsettableShape>: View {
    @Environment(\.sceneTheme) private var theme
    let shape: S
    let isSelected: Bool

    var body: some View {
        shape.strokeBorder(
            Color(role: isSelected ? .bgAccent : .borderDefault, in: theme),
            lineWidth: isSelected ? Sizing.selectionStroke : Sizing.hairline)
    }
}

/// The solid accent disc with a check that marks a picked choice.
public struct CheckBadge: View {
    @Environment(\.sceneTheme) private var theme
    private let glyph: Double = 10

    public init() {}

    public var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: glyph, weight: .heavy))
            .foregroundStyle(Color(role: .fgOnAccent, in: theme))
            .frame(width: Sizing.checkBadge, height: Sizing.checkBadge)
            .background(Color(role: .bgAccent, in: theme), in: Circle())
            .accessibilityHidden(true)
    }
}

/// A color to dress the character in: a 32-point disc with a faint edge, so white shows on white.
/// Picked, a white gap and an accent ring go around it. It answers taps across 44 points.
public struct Swatch: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var taps = 0
    private let color: Color
    private let label: Text
    private let isSelected: Bool
    private let action: () -> Void

    /// The white gap between the disc and the ring of a picked swatch.
    private let gap: Double = 2.5

    public init(_ color: Color, label: Text, isSelected: Bool, action: @escaping () -> Void) {
        self.color = color
        self.label = label
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            Circle()
                .fill(color)
                .overlay(
                    Circle().strokeBorder(Color(role: .fgDefault, in: theme).opacity(0.1), lineWidth: Sizing.hairline)
                )
                .frame(width: Sizing.swatch, height: Sizing.swatch)
                .padding(gap)
                .overlay {
                    if isSelected {
                        Circle().strokeBorder(Color(role: .bgAccent, in: theme), lineWidth: Sizing.selectionStroke)
                            .padding(-Sizing.selectionStroke)
                            .transition(.opacity)
                    }
                }
                .frame(width: Sizing.minimumTapTarget, height: Sizing.minimumTapTarget)
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .animation(.wildcard(Motion.change, reduceMotion: reduceMotion), value: isSelected)
        .sensoryFeedback(.selection, trigger: taps)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
#endif
