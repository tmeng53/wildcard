#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import ScheduleDomain
import SwiftUI

/// One day's swim lane on the poster: its `ScheduleDayRow` (weekday, the sport's disc, plan and
/// mark), shaded by how it is held. A button, so the member picks the day by tapping it.
struct PosterLane: View {
    static let height: Double = 40

    let lane: PosterContent.Lane
    let theme: SceneTheme
    let colors: PosterColors
    let onTap: (Int) -> Void

    // From the approved design, in poster points.
    /// Lanes alternate with a faint shade; today's is darker.
    private let stripeShade = 0.06
    private let todayShade = 0.18

    private var isHeld: Bool { lane.look == .held }
    private var ink: Color { Color(role: colors.ink, in: theme) }
    private var shade: Color { Color(role: colors.shade, in: theme) }

    var body: some View {
        Button {
            onTap(lane.index)
        } label: {
            row
                .foregroundStyle(isHeld ? Color(role: colors.onInk, in: theme) : ink)
                .padding(.horizontal, Space.m)
                .frame(maxWidth: .infinity)
                .frame(height: Self.height)
                .background { fill }
                .overlay(alignment: .bottom) {
                    LaneRope(isPool: theme == .pool && colors == .scene, color: ink)
                        .frame(height: 4)
                        .offset(y: 2)
                        .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
        }
        // Pressable, not plain: a plain button fades while disabled, and a locked day reads as
        // clearly as one still to come.
        .buttonStyle(PressableButtonStyle())
        .zIndex(isHeld ? 1 : 0)
        .disabled(!lane.isEditable)
        .accessibilityLabel(row.accessibilityText)
        .accessibilityAddTraits(isHeld ? .isSelected : [])
        .accessibilityIdentifier("schedule.lane.\(lane.index)")
    }

    private var row: ScheduleDayRow {
        let glyph = Color(role: colors.onInk, in: theme)
        return ScheduleDayRow(
            day: lane.day, isToday: lane.isToday, shown: lane.shown, mark: lane.mark,
            colors: isHeld
                ? .init(ink: glyph, onInk: ink, markDisc: Color(role: colors.heldDisc, in: theme), markGlyph: glyph)
                : .init(ink: ink, onInk: glyph, markDisc: ink, markGlyph: glyph),
            fadesRest: !isHeld)
    }

    @ViewBuilder
    private var fill: some View {
        switch lane.look {
        case .held: ink
        case .today: shade.opacity(todayShade)
        case .plain: lane.index.isMultiple(of: 2) ? Color.clear : shade.opacity(stripeShade)
        }
    }
}

/// The dotted lane rope along the bottom of each lane: pool floats, or a fine dotted line on
/// the other scenes.
private struct LaneRope: View {
    let isPool: Bool
    let color: Color

    var body: some View {
        Canvas { context, size in
            let gap = isPool ? 9.0 : 4.0
            let radius = isPool ? 2.2 : 0.9
            let color = color.opacity(isPool ? 0.75 : 0.6)
            var left = 4.0
            while left < size.width {
                let dot = CGRect(
                    x: left - radius, y: size.height / 2 - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: dot), with: .color(color))
                left += gap
            }
        }
    }
}
#endif
