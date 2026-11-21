#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// The four check-in kinds 打卡's ＋ opens into (Tracy, 2026-11-21): clear Liquid Glass capsules
/// stacked above the ＋ at the tab bar's trailing end, the narrowest on top and the widest next to
/// the ＋. Put it over a tab's screen, under the bar, so the ＋, now a cross, still closes it; the
/// caller blurs the screen while it is open (`Scrim`). A tap outside closes it; a pick closes it
/// and calls `onPick`.
///
/// A kind in `unavailable` is left out: a choice the member can't make isn't shown. Each capsule
/// is `<identifierPrefix>.capsule.<kind>` for UI tests.
public struct CheckInMenu: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding private var isOpen: Bool
    private let unavailable: Set<CheckInKind>
    private let identifierPrefix: String
    private let onPick: (CheckInKind) -> Void
    @State private var picks = 0
    // Measured, so the stack goes by width whatever the language and text size.
    @State private var widths: [CheckInKind: Double] = [:]

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
        let kinds = stacked
        ZStack(alignment: .bottomTrailing) {
            if isOpen {
                // A tap anywhere outside the capsules closes the menu.
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { close() }
                    .accessibilityHidden(true)
            }
            GlassEffectContainer {
                VStack(alignment: .trailing, spacing: Space.s) {
                    if isOpen {
                        ForEach(Array(kinds.enumerated()), id: \.element) { index, kind in
                            MenuCapsule(kind: kind) {
                                picks += 1
                                close()
                                onPick(kind)
                            }
                            .accessibilityIdentifier("\(identifierPrefix).capsule.\(kind.rawValue)")
                            .accessibilityAction(.escape) { close() }
                            // The one next to the ＋ first, the rest following up the stack.
                            .transition(pop(index: kinds.count - 1 - index, of: kinds.count))
                        }
                    }
                }
                .padding(.trailing, Space.m)
                .padding(.bottom, Space.s)
            }
        }
        .background { measuring }
        // Haptics only where the spec puts them: the menu opening and picking a kind.
        .haptic(.appear, trigger: isOpen) { _, opened in opened }
        .haptic(.pick, trigger: picks)
    }

    private func close() {
        withAnimation(.wildcard(Motion.sheet.exit, reduceMotion: reduceMotion)) { isOpen = false }
    }

    /// The kinds shown, narrowest on top: in the order the stack reads down once all are measured,
    /// else the kinds' own order.
    private var stacked: [CheckInKind] {
        let kinds = CheckInKind.allCases.filter { !unavailable.contains($0) }
        guard kinds.allSatisfy({ widths[$0] != nil }) else { return kinds }
        return kinds.enumerated()
            .sorted { lhs, rhs in
                let (left, right) = (widths[lhs.element] ?? 0, widths[rhs.element] ?? 0)
                return left == right ? lhs.offset < rhs.offset : left < right
            }
            .map(\.element)
    }

    /// Invisible copies of the capsules, always laid out, to read their widths.
    private var measuring: some View {
        ZStack {
            ForEach(CheckInKind.allCases, id: \.self) { kind in
                MenuCapsuleLabel(kind: kind)
                    .onGeometryChange(for: Double.self, of: { $0.size.width }, action: { widths[kind] = $0 })
            }
        }
        .hidden()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    /// Up out of the ＋ like a bubble, one after another; back in faster, the top one first.
    private func pop(index: Int, of count: Int) -> AnyTransition {
        if reduceMotion {
            return .opacity.animation(.easeOut(duration: Motion.reducedDuration))
        }
        let shape = AnyTransition.scale(scale: 0.3, anchor: .bottomTrailing).combined(with: .opacity)
        return .asymmetric(
            insertion: shape.animation(.wildcard(Motion.sheet).delay(Motion.burstStagger * Double(index))),
            removal: shape.animation(
                .easeIn(duration: Motion.collapseDuration)
                    .delay(Motion.collapseStagger * Double(count - 1 - index)))
        )
    }
}

/// A capsule's icon and name at their natural size.
private struct MenuCapsuleLabel: View {
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

/// One check-in kind on clear glass.
private struct MenuCapsule: View {
    let kind: CheckInKind
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MenuCapsuleLabel(kind: kind)
                .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .glassEffect(.regular.interactive(), in: Capsule())
    }
}
#endif
