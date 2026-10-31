#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// The 打卡 button and the four check-in capsules it opens into, on an arc above it. The button
/// is the screen's primary action, a solid capsule in the scene's accent; the capsules are clear
/// Liquid Glass with the icon in the accent's text color. The caller owns `isOpen`, so it can blur
/// the scene behind an open burst and close it from a tap outside.
///
/// A type in `unavailable` is left out, and the others share the arc: a choice the member can't
/// make isn't shown.
public struct CheckInBurst: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding private var isOpen: Bool
    private let unavailable: Set<CheckInKind>
    private let identifierPrefix: String
    private let onPick: (CheckInKind) -> Void
    @State private var picks = 0
    // Measured, so the capsules stand apart whatever the language and text size.
    @State private var widths: [CheckInKind: Double] = [:]
    @State private var button = CGSize(width: 0, height: Sizing.primaryControl)
    @State private var screenWidth: Double = 0

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
        let kinds = shown
        let spots = positions(of: kinds)
        return GlassEffectContainer {
            ZStack {
                if isOpen {
                    ForEach(Array(kinds.enumerated()), id: \.element) { index, kind in
                        BurstCapsule(kind: kind) {
                            picks += 1
                            withAnimation(.wildcard(Motion.sheet.exit, reduceMotion: reduceMotion)) { isOpen = false }
                            onPick(kind)
                        }
                        .accessibilityIdentifier("\(identifierPrefix).capsule.\(kind.rawValue)")
                        .offset(x: spots[index].x, y: spots[index].y)
                        .transition(burst(index: index, of: kinds.count, spot: spots[index]))
                    }
                }
                BurstButton(isOpen: $isOpen)
                    .accessibilityIdentifier("\(identifierPrefix).checkin")
                    .onGeometryChange(for: CGSize.self, of: \.size) { button = $0 }
            }
        }
        .frame(height: Sizing.primaryControl)
        .background { measuring }
        // Haptics only where the spec puts them: the burst opening and picking a type.
        .haptic(.appear, trigger: isOpen) { _, opened in opened }
        .haptic(.pick, trigger: picks)
    }

    private var shown: [CheckInKind] { CheckInKind.allCases.filter { !unavailable.contains($0) } }

    /// Each capsule's center, from the widths measured below; the arc until they are known.
    private func positions(of kinds: [CheckInKind]) -> [(x: Double, y: Double)] {
        let measured = kinds.compactMap { widths[$0] }
        guard measured.count == kinds.count, screenWidth > 0 else { return BurstLayout.arc(for: kinds) }
        return BurstLayout.positions(
            kinds: kinds, widths: measured, height: Sizing.control,
            button: (width: button.width, height: button.height),
            available: screenWidth)
    }

    /// Invisible copies of the capsules, always laid out, and the screen's width.
    private var measuring: some View {
        ZStack {
            ForEach(CheckInKind.allCases, id: \.self) { kind in
                BurstCapsuleLabel(kind: kind)
                    .onGeometryChange(for: Double.self, of: { $0.size.width }, action: { widths[kind] = $0 })
            }
        }
        .hidden()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .background {
            Color.clear.containerRelativeFrame(.horizontal)
                .onGeometryChange(for: Double.self, of: { $0.size.width }, action: { screenWidth = $0 })
        }
    }

    /// Out of the button along the arc, staggered; back in faster, in reverse order.
    private func burst(index: Int, of count: Int, spot: (x: Double, y: Double)) -> AnyTransition {
        if reduceMotion {
            return .opacity.animation(.easeOut(duration: Motion.reducedDuration))
        }
        let shape = AnyTransition.offset(x: -spot.x, y: -spot.y)
            .combined(with: .scale(scale: 0.4))
            .combined(with: .opacity)
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

/// A capsule's icon and name at their natural size.
private struct BurstCapsuleLabel: View {
    @Environment(\.sceneTheme) private var theme
    let kind: CheckInKind

    var body: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: kind.symbol)
                .font(.system(size: Sizing.kindIcon * 0.8, weight: .semibold))
                .frame(width: Sizing.kindIcon, height: Sizing.kindIcon)
                .foregroundStyle(Color(role: .fgAccent, in: theme))
                .accessibilityHidden(true)
            kind.shortName
                .typeStyle(TypeRamp.callout)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .fixedSize()
        }
        .padding(.horizontal, Space.m)
        .frame(height: Sizing.control)
    }
}

/// One check-in type on clear glass.
private struct BurstCapsule: View {
    let kind: CheckInKind
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            BurstCapsuleLabel(kind: kind)
                .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .glassEffect(.regular.interactive(), in: Capsule())
    }
}
#endif
