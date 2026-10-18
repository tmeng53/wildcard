#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// The 打卡 button and the four check-in capsules it bursts into, on an arc above it. Both
/// are Liquid Glass: the button tinted with the scene's signature, the capsules clear (spec
/// rev 186, Tracy 2026-10-18 22:50Z). The caller owns `isOpen`, so it can blur the scene
/// behind an open burst and close it from a tap outside.
///
/// A type in `unavailable` shows grey; tapping it shakes it and picks nothing.
public struct CheckInBurst: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding private var isOpen: Bool
    private let unavailable: Set<Meaning>
    private let identifierPrefix: String
    private let onPick: (Meaning) -> Void
    @State private var picked: Meaning?

    /// `identifierPrefix` names the button `<prefix>.checkin` and each capsule
    /// `<prefix>.capsule.<meaning>` for UI tests.
    public init(
        isOpen: Binding<Bool>, unavailable: Set<Meaning> = [], identifierPrefix: String,
        onPick: @escaping (Meaning) -> Void
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
                    ForEach(Array(Meaning.allCases.enumerated()), id: \.element) { index, meaning in
                        BurstCapsule(meaning: meaning, isAvailable: !unavailable.contains(meaning)) {
                            picked = meaning
                            withAnimation(.wildcard(Motion.burst, reduceMotion: reduceMotion)) { isOpen = false }
                            onPick(meaning)
                        }
                        .accessibilityIdentifier("\(identifierPrefix).capsule.\(meaning.rawValue)")
                        .offset(x: BurstLayout.offset(for: meaning).x, y: BurstLayout.offset(for: meaning).y)
                        .transition(burst(for: meaning, index: index))
                    }
                }
                BurstButton(isOpen: $isOpen)
                    .accessibilityIdentifier("\(identifierPrefix).checkin")
            }
        }
        .frame(height: Sizing.checkInHeight)
        // Haptics only where the spec puts them: the burst opening and picking a type.
        .sensoryFeedback(.impact(weight: .light), trigger: isOpen) { _, opened in opened }
        .sensoryFeedback(.selection, trigger: picked)
    }

    /// Out of the button along the arc, staggered; back in faster, in reverse order.
    private func burst(for meaning: Meaning, index: Int) -> AnyTransition {
        if reduceMotion {
            return .opacity.animation(.easeOut(duration: Motion.reducedDuration))
        }
        let offset = BurstLayout.offset(for: meaning)
        let shape = AnyTransition.offset(x: -offset.x, y: -offset.y)
            .combined(with: .scale(scale: 0.4))
            .combined(with: .opacity)
        let count = Meaning.allCases.count
        return .asymmetric(
            insertion: shape.animation(.wildcard(Motion.burst).delay(Motion.burstStagger * Double(index))),
            removal: shape.animation(
                .easeIn(duration: Motion.collapseDuration)
                    .delay(Motion.collapseStagger * Double(count - 1 - index)))
        )
    }
}

/// The primary action: signature-tinted glass. Its plus turns into a cross and it keeps a
/// word (收起) when open, so it is never an icon alone.
private struct BurstButton: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var isOpen: Bool

    var body: some View {
        Button {
            withAnimation(.wildcard(Motion.burst, reduceMotion: reduceMotion)) { isOpen.toggle() }
        } label: {
            HStack(spacing: Space.xs) {
                Image(systemName: "plus")
                    .fontWeight(.bold)
                    .rotationEffect(.degrees(isOpen ? 135 : 0))
                    .accessibilityHidden(true)
                (isOpen ? Text("收起", bundle: .module) : Text("打卡", bundle: .module))
                    .typeStyle(TypeRamp.action)
            }
            .foregroundStyle(Color(role: .onSignature, in: theme))
            .padding(.horizontal, Space.l)
            .frame(minHeight: Sizing.checkInHeight)
            .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .glassEffect(.regular.tint(Color(role: .signature, in: theme)).interactive(), in: Capsule())
    }
}

/// One check-in type on clear glass. Unavailable, it greys out and shakes when tapped.
private struct BurstCapsule: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let meaning: Meaning
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
                Image(systemName: meaning.symbol)
                    .font(.system(size: Sizing.capsuleGlyph, weight: .semibold))
                    .frame(width: Sizing.capsuleIcon, height: Sizing.capsuleIcon)
                    .foregroundStyle(Color(role: isAvailable ? meaning.ink : .textTertiary, in: theme))
                    .accessibilityHidden(true)
                meaning.capsuleLabel
                    .typeStyle(TypeRamp.callout)
                    .foregroundStyle(Color(role: isAvailable ? .textPrimary : .textTertiary, in: theme))
                    .fixedSize()
            }
            .padding(.horizontal, Space.m)
            .frame(height: Sizing.capsuleHeight)
            .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .glassEffect(.regular.interactive(), in: Capsule())
        .keyframeAnimator(initialValue: 0.0, trigger: refusals) { content, shift in
            content.offset(x: reduceMotion ? 0 : shift)
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(-6, duration: 0.08)
                LinearKeyframe(5, duration: 0.08)
                LinearKeyframe(-3, duration: 0.08)
                LinearKeyframe(0, duration: 0.08)
            }
        }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.4), trigger: refusals)
    }
}
#endif
