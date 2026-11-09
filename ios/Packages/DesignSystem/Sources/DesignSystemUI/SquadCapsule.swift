#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// The squad card folded into a capsule of scene glass at the top of home (the approved 收起,
/// 2026-11-06), so the scene shows: the squad's heads with its week's score under them, a line,
/// then my week, Monday to Sunday, today named 今天. A grabber at its foot says it opens; a tap
/// or a swipe down calls `expand`, and the caller swaps in the `SquadCard` (both carry the same
/// glass, so the system morphs one into the other). The caller draws `heads` (at most three,
/// and the rest as 「+N」, sized by `SquadCapsuleLayout`), since the characters live outside the
/// design system.
public struct SquadCapsule<Heads: View>: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let squad: SquadWeek
    private let mine: MyWeek
    private let expand: () -> Void
    private let heads: Heads
    private var morph: GlassMorph?
    /// How far a swipe down has stretched the capsule, while the finger is down.
    @State private var stretch = 0.0

    public init(squad: SquadWeek, mine: MyWeek, @ViewBuilder heads: () -> Heads, expand: @escaping () -> Void) {
        self.squad = squad
        self.mine = mine
        self.heads = heads()
        self.expand = expand
    }

    public var body: some View {
        Button(action: expand) {
            HStack(spacing: Space.s) {
                VStack(spacing: SquadCardMetrics.compactDayGap) {
                    heads
                    score
                }
                .fixedSize()
                Rectangle()
                    .fill(Color(role: .fgDefault, in: theme).opacity(SquadCardMetrics.dividerOpacity))
                    .frame(width: Sizing.hairline, height: SquadCardMetrics.capsuleDivider)
                week
            }
            .padding(.horizontal, Space.s)
            .padding(.bottom, Space.xs)
            .frame(maxWidth: .infinity, minHeight: SquadCardMetrics.capsuleHeight + stretch)
            .overlay(alignment: .bottom) {
                Grabber()
                    .padding(.bottom, Space.xs - 2)
            }
            .contentShape(Capsule())
            .accessibilityElement(children: .ignore)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(Text("展开小队卡片", bundle: .module))
        .accessibilityValue(
            Text("\(squad.name)，本周 \(squad.done)/\(squad.goal) 次；我这周 \(mine.done)/\(mine.planned)", bundle: .module)
        )
        .accessibilityIdentifier("squadcard.capsule")
        .sceneGlass(in: Capsule(), theme: theme, interactive: true, morph: morph)
        .simultaneousGesture(pullDown)
        .padding(.horizontal, Space.pageMargin)
        .accessibilityElement(children: .contain)
    }

    /// The capsule's glass morphs into the glass with the same id, the open card.
    public func morphs(_ morph: GlassMorph) -> Self {
        var capsule = self
        capsule.morph = morph
        return capsule
    }

    /// The squad's week under the heads: 7/16 天.
    private var score: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xxs / 2) {
            Score(count: squad.done, goal: squad.goal, size: .small)
            Text("次", bundle: .module)
                .typeStyle(TypeRamp.denominator(of: TypeRamp.scoreSmall))
                .foregroundStyle(Color(role: .fgSubtle, in: theme))
        }
        .lineLimit(1)
    }

    /// My week, Monday to Sunday, spread across what is left of the capsule.
    private var week: some View {
        WeekDayRow(days: mine.days, today: mine.today)
    }

    /// A swipe down stretches the capsule after the finger and, past `SquadCardMetrics.fold`,
    /// opens the card.
    private var pullDown: some Gesture {
        DragGesture(minimumDistance: SquadCardMetrics.dragStart)
            .onChanged { value in
                guard value.isVertical else { return }
                stretch = max(0, value.translation.height) * SquadCardMetrics.rubber
            }
            .onEnded { value in
                let opens = value.isVertical && value.translation.height > SquadCardMetrics.fold
                withAnimation(.wildcard(Motion.sheet, reduceMotion: reduceMotion)) { stretch = 0 }
                if opens { expand() }
            }
    }
}

/// What a caller drawing the capsule's heads needs to know.
public enum SquadCapsuleLayout {
    /// Each head's size.
    public static let head: Double = SquadCardMetrics.capsuleHead
    /// Heads before the rest fold into 「+N」.
    public static let heads = 3
}
#endif
