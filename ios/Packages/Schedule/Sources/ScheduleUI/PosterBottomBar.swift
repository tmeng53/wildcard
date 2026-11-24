#if os(iOS)
import DesignSystem
import DesignSystemUI
import ScheduleDomain
import SwiftUI

/// What the poster's bottom strip holds: the week's count.
struct PosterBottomBar: View {
    let content: PosterContent
    let theme: SceneTheme
    let colors: PosterColors

    var body: some View {
        HStack(spacing: Space.xs) {
            Spacer(minLength: 0)
            tally
        }
        .padding(.leading, Space.s - 2)
        .padding(.trailing, Space.s)
    }

    private var tally: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xs - 2) {
            switch content.tally {
            case .trained(let trained, let planned, let isPast):
                Group {
                    if isPast { Text(copy: "训练", bundle: .module) } else { Text(copy: "本周", bundle: .module) }
                }
                .typeStyle(TypeRamp.label)
                Text(verbatim: "\(trained)/\(planned)")
                    .typeStyle(TypeRamp.scoreInline)
                    .contentTransition(.numericText(value: Double(trained)))
            case .planned(let train, let rest):
                Text(copy: "\(train) 练 \(rest) 休", bundle: .module)
                    .typeStyle(TypeRamp.calloutEmphasis)
                    .contentTransition(.numericText(value: Double(train)))
            case .typical(let train):
                Text(copy: "每周训练", bundle: .module)
                    .typeStyle(TypeRamp.label)
                Text(verbatim: "\(train)")
                    .typeStyle(TypeRamp.scoreInline)
                    .contentTransition(.numericText(value: Double(train)))
                Text(copy: "天", bundle: .module)
                    .typeStyle(TypeRamp.label)
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("schedule.tally")
    }
}
#endif
