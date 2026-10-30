#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import ScheduleDomain
import SwiftUI

/// One day's swim lane on the poster: its number, weekday, plan and mark, shaded by how it is
/// held. A button, so the member picks the day by tapping it.
struct PosterLane: View {
    static let height: Double = 40

    let lane: PosterContent.Lane
    let theme: SceneTheme
    let onTap: (Int) -> Void

    // From the approved design, in poster points.
    /// Lanes alternate with a faint shade; today's is darker.
    private let stripeShade = 0.06
    private let todayShade = 0.18
    /// Days off fade back, so the training days read first.
    private let restOpacity = 0.55
    private let restNumberOpacity = 0.4
    private let numberOpacity = 0.9
    private let markSize: Double = 17
    private let leaveTagHeight: Double = 20
    private let numberWidth: Double = 20
    private let weekdayWidth: Double = 30

    private var isHeld: Bool { lane.look == .held }
    private var isFaded: Bool { lane.plan == .rest && !isHeld }
    private var ink: Color { Color(role: .bgCanvas, in: theme) }
    private var shade: Color { Color(role: .fgDefault, in: theme) }

    var body: some View {
        Button {
            onTap(lane.index)
        } label: {
            row
                .foregroundStyle(isHeld ? Color(role: .fgAccent, in: theme) : ink)
                .padding(.horizontal, Space.m)
                .frame(width: WeekPoster.size.width, height: Self.height)
                .background { fill }
                .overlay(alignment: .bottom) {
                    LaneRope(theme: theme)
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
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isHeld ? .isSelected : [])
        .accessibilityIdentifier("schedule.lane.\(lane.index)")
    }

    private var row: some View {
        HStack(spacing: Space.s - 2) {
            Text(verbatim: "\(lane.index + 1)")
                .typeStyle(TypeRamp.scoreInline)
                .frame(width: numberWidth, alignment: .leading)
                .opacity(isFaded ? restNumberOpacity : numberOpacity)
            Group {
                if lane.isToday {
                    Text("今天", bundle: .module)
                } else {
                    ScheduleLabels.weekday(lane.day)
                }
            }
            .typeStyle(TypeRamp.label)
            // English's "Today" is a touch wider than the column: it shrinks rather than wraps.
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: weekdayWidth, alignment: .leading)
            ScheduleLabels.plan(lane.plan)
                .typeStyle(TypeRamp.headline)
                .lineLimit(1)
                .opacity(isFaded ? restOpacity : 1)
            mark
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var fill: some View {
        switch lane.look {
        case .held: ink
        case .today: shade.opacity(todayShade)
        case .plain: lane.index.isMultiple(of: 2) ? Color.clear : shade.opacity(stripeShade)
        }
    }

    /// A tick for a day trained, 请假 for a 请假条.
    @ViewBuilder
    private var mark: some View {
        let disc = isHeld ? Color(role: .bgAccentSubtle, in: theme) : ink
        let glyph = Color(role: .fgAccent, in: theme)
        switch lane.mark {
        case .trained:
            Image(systemName: "checkmark")
                .font(.system(size: markSize * 0.55, weight: .heavy))
                .foregroundStyle(glyph)
                .frame(width: markSize, height: markSize)
                .background(disc, in: Circle())
                .accessibilityHidden(true)
        case .disclaimer:
            Text("请假", bundle: .module)
                .typeStyle(TypeRamp.label)
                .foregroundStyle(glyph)
                .padding(.horizontal, Space.xs - 1)
                .frame(height: leaveTagHeight)
                .background(disc, in: Capsule())
        case .none:
            EmptyView()
        }
    }

    private var accessibilityLabel: Text {
        let day = lane.isToday ? Text("今天", bundle: .module) : ScheduleLabels.weekday(lane.day)
        let status: Text =
            switch lane.mark {
            case .trained: Text("，练了", bundle: .module)
            case .disclaimer: Text("，请假", bundle: .module)
            case .none: Text(verbatim: "")
            }
        return Text("\(day) \(ScheduleLabels.plan(lane.plan))\(status)", bundle: .module)
    }
}

/// The dotted lane rope along the bottom of each lane: pool floats, or a fine dotted line on
/// the other scenes.
private struct LaneRope: View {
    let theme: SceneTheme

    var body: some View {
        Canvas { context, size in
            let isPool = theme == .pool
            let gap = isPool ? 9.0 : 4.0
            let radius = isPool ? 2.2 : 0.9
            let color = Color(role: .bgCanvas, in: theme).opacity(isPool ? 0.75 : 0.6)
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
