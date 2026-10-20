#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// The 打卡 button and the four check-in capsules it opens into, on an arc above it. The button
/// is the screen's primary action, a solid capsule in the scene's accent; the capsules are clear
/// Liquid Glass with the icon in the accent's text color. The caller owns `isOpen`, so it can blur
/// the scene behind an open burst and close it from a tap outside.
///
/// A type in `unavailable` shows grey; tapping it shakes it and picks nothing.
public struct CheckInBurst: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding private var isOpen: Bool
    private let unavailable: Set<CheckInKind>
    private let identifierPrefix: String
    private let onPick: (CheckInKind) -> Void
    @State private var picks = 0

    /// `identifierPrefix` names the button `<prefix>.checkin` and each capsule
    /// `<prefix>.capsule.<kind>` for UI tests.
    public init(
        isOpen: Binding<Bool>, unavailable: Set<CheckInKind> = [], identifierPrefix: String,
        onPick: @escaping (CheckInKind) -> Void
    ) {
        _isOpen = isOpen
        self.unavailable = unavailable
        self.identifierPrefix = identifierPrefix
        self.onPick = onPick
    }

    public var body: some View {
        GlassEffectContainer {
            ZStack {
                if isOpen {
                    ForEach(Array(CheckInKind.allCases.enumerated()), id: \.element) { index, kind in
                        BurstCapsule(kind: kind, isAvailable: !unavailable.contains(kind)) {
                            picks += 1
                            withAnimation(.wildcard(Motion.sheet.exit, reduceMotion: reduceMotion)) { isOpen = false }
                            onPick(kind)
                        }
                        .accessibilityIdentifier("\(identifierPrefix).capsule.\(kind.rawValue)")
                        .offset(x: BurstLayout.offset(for: kind).x, y: BurstLayout.offset(for: kind).y)
                        .transition(burst(for: kind, index: index))
                    }
                }
                BurstButton(isOpen: $isOpen)
                    .accessibilityIdentifier("\(identifierPrefix).checkin")
            }
        }
        .frame(height: Sizing.primaryControl)
        // Haptics only where the spec puts them: the burst opening and picking a type.
        .haptic(.appear, trigger: isOpen) { _, opened in opened }
        .haptic(.pick, trigger: picks)
    }

    /// Out of the button along the arc, staggered; back in faster, in reverse order.
    private func burst(for kind: CheckInKind, index: Int) -> AnyTransition {
        if reduceMotion {
            return .opacity.animation(.easeOut(duration: Motion.reducedDuration))
        }
        let offset = BurstLayout.offset(for: kind)
        let shape = AnyTransition.offset(x: -offset.x, y: -offset.y)
            .combined(with: .scale(scale: 0.4))
            .combined(with: .opacity)
        let count = CheckInKind.allCases.count
        return .asymmetric(
            insertion: shape.animation(.wildcard(Motion.sheet).delay(Motion.burstStagger * Double(index))),
            removal: shape.animation(
                .easeIn(duration: Motion.collapseDuration)
                    .delay(Motion.collapseStagger * Double(count - 1 - index)))
        )
    }
}

/// The primary action: a solid accent capsule. Its plus turns into a cross and it keeps a word
/// (收起) when open, so it is never an icon alone.
private struct BurstButton: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var isOpen: Bool

    /// The design's insets: 22 on the plus's side, 28 on the word's side, around the primary
    /// button's own `Space.l`.
    private static let iconSide: Double = 22
    private static let textSide: Double = 28

    var body: some View {
        Button {
            withAnimation(.wildcard(isOpen ? Motion.sheet.exit : Motion.sheet, reduceMotion: reduceMotion)) {
                isOpen.toggle()
            }
        } label: {
            HStack(spacing: Space.xs) {
                Image(systemName: "plus")
                    .fontWeight(.bold)
                    .rotationEffect(.degrees(isOpen ? 135 : 0))
                    .accessibilityHidden(true)
                if isOpen {
                    Text("收起", bundle: .module)
                } else {
                    Text("打卡", bundle: .module)
                }
            }
            .padding(.leading, Self.iconSide - Space.l)
            .padding(.trailing, Self.textSide - Space.l)
        }
        .buttonStyle(PrimaryButtonStyle())
    }
}

/// One check-in type on clear glass. Unavailable, it greys out and shakes when tapped.
private struct BurstCapsule: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let kind: CheckInKind
    let isAvailable: Bool
    let action: () -> Void
    @State private var refusals = 0

    var body: some View {
        Button {
            if isAvailable {
                action()
            } else {
                refusals += 1
            }
        } label: {
            HStack(spacing: Space.xs) {
                Image(systemName: kind.symbol)
                    .font(.system(size: Sizing.kindIcon * 0.8, weight: .semibold))
                    .frame(width: Sizing.kindIcon, height: Sizing.kindIcon)
                    .foregroundStyle(Color(role: isAvailable ? .fgAccent : .fgSubtle, in: theme))
                    .accessibilityHidden(true)
                kind.shortName
                    .typeStyle(TypeRamp.callout)
                    .foregroundStyle(Color(role: isAvailable ? .fgDefault : .fgSubtle, in: theme))
                    .fixedSize()
            }
            .padding(.horizontal, Space.m)
            .frame(height: Sizing.control)
            .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .glassEffect(.regular.interactive(), in: Capsule())
        .shake(trigger: refusals, reduceMotion: reduceMotion)
    }
}
#endif
