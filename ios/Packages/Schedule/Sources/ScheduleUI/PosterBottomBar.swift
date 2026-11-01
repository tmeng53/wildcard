#if os(iOS)
import DesignSystem
import DesignSystemUI
import ScheduleDomain
import SwiftUI

/// What the poster's bottom strip holds: the week's 饮食小目标, a button next week, and the
/// week's count.
struct PosterBottomBar: View {
    let content: PosterContent
    let theme: SceneTheme
    let colors: PosterColors
    let onTapFuel: () -> Void

    private var ink: Color { Color(role: colors.ink, in: theme) }

    var body: some View {
        HStack(spacing: Space.xs) {
            // The 每周模板 has no 饮食小目标: each week picks its own.
            if !content.isTemplate {
                fuelButton
            }
            Spacer(minLength: 0)
            tally
        }
        .padding(.leading, Space.s - 2)
        .padding(.trailing, Space.s)
    }

    private var fuelButton: some View {
        let open = content.fuelOpen
        return Button(action: onTapFuel) {
            HStack(spacing: Space.xs - 2) {
                Image(systemName: "fork.knife")
                    .font(.system(size: Sizing.smallIcon - 2, weight: .semibold))
                    .accessibilityHidden(true)
                fuelLabel
                    .typeStyle(TypeRamp.footnoteEmphasis)
                    .lineLimit(1)
            }
            .foregroundStyle(open ? Color(role: colors.onInk, in: theme) : ink)
            .padding(.horizontal, Space.s)
            .frame(height: Sizing.compactControl - Space.xxs)
            .background(open ? ink : Color.clear, in: Capsule())
            .frame(minHeight: WeekPosterLayout.stripHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!content.fuelEditable)
        .accessibilityAddTraits(open ? .isSelected : [])
        .accessibilityIdentifier("schedule.fuel")
    }

    /// Every goal when they fit; otherwise the first and how many more, never cut off.
    @ViewBuilder
    private var fuelLabel: some View {
        let names = content.fuel.map(ScheduleLabels.fuelName)
        if let first = names.first {
            ViewThatFits(in: .horizontal) {
                Text(verbatim: names.joined(separator: " · "))
                Text(verbatim: names.count > 1 ? "\(first) +\(names.count - 1)" : first)
                    .minimumScaleFactor(0.7)
            }
        } else {
            Text("饮食", bundle: .module)
        }
    }

    private var tally: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xs - 2) {
            switch content.tally {
            case .trained(let trained, let planned, let isPast):
                Group {
                    if isPast { Text("练了", bundle: .module) } else { Text("本周", bundle: .module) }
                }
                .typeStyle(TypeRamp.label)
                Text(verbatim: "\(trained)/\(planned)")
                    .typeStyle(TypeRamp.scoreInline)
                    .contentTransition(.numericText(value: Double(trained)))
            case .planned(let train, let rest):
                Text("\(train) 练 \(rest) 休", bundle: .module)
                    .typeStyle(TypeRamp.calloutEmphasis)
                    .contentTransition(.numericText(value: Double(train)))
            case .typical(let train):
                Text("每周训练", bundle: .module)
                    .typeStyle(TypeRamp.label)
                Text(verbatim: "\(train)")
                    .typeStyle(TypeRamp.scoreInline)
                    .contentTransition(.numericText(value: Double(train)))
                Text("天", bundle: .module)
                    .typeStyle(TypeRamp.label)
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("schedule.tally")
    }
}
#endif
