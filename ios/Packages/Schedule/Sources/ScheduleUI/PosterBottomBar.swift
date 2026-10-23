#if os(iOS)
import DesignSystem
import DesignSystemUI
import ScheduleDomain
import SwiftUI

/// The poster's bottom bar: the week's 饮食小目标, a button next week, and the week's count.
struct PosterBottomBar: View {
    static let height: Double = 44

    let content: PosterContent
    let theme: SceneTheme
    let onTapFuel: () -> Void

    private let barShade = 0.16

    private var ink: Color { Color(role: .bgCanvas, in: theme) }

    var body: some View {
        HStack(spacing: Space.xs) {
            fuelButton
            Spacer(minLength: 0)
            tally
        }
        .padding(.leading, Space.s - 2)
        .padding(.trailing, Space.s)
        .frame(width: WeekPoster.size.width, height: Self.height)
        .background(Color(role: .fgDefault, in: theme).opacity(barShade))
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
            .foregroundStyle(open ? Color(role: .fgAccent, in: theme) : ink)
            .padding(.horizontal, Space.s)
            .frame(height: Sizing.compactControl - Space.xxs)
            .background(open ? ink : Color.clear, in: Capsule())
            .frame(minHeight: Self.height)
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
            Text("饮食小目标", bundle: .module)
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
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("schedule.tally")
    }
}
#endif
