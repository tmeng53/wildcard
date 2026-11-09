#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import SquadDomain
import SwiftUI

/// 小队's 每周目标 (approved 2026-11-06): the goal and how the squad did lately as two
/// scoreboard numbers on graphite, 「目标 · 人均 3 次」 and 「最近 4 周 · 人均 3.4 次」 (left out
/// until a week has finished). The captain picks 1 to 7 under them; a change counts from next
/// week, which the line under the card says. Everyone else reads it only.
struct SquadGoalCard: View {
    let goal: SquadWeeklyGoal
    let canChange: Bool
    let pick: (Int) -> Void
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            VStack(alignment: .leading, spacing: Space.m) {
                HStack(alignment: .top, spacing: Space.m) {
                    Figure(
                        label: Text(copy: "目标 · 人均", bundle: .module), value: Text(verbatim: "\(goal.daysPerMember)")
                    )
                    .accessibilityIdentifier("squad.goal.now")
                    if let recent = goal.recent {
                        Rectangle()
                            .fill(Color(role: .fgOnInkMuted, in: theme).opacity(0.5))
                            .frame(width: Sizing.hairline)
                            .accessibilityHidden(true)
                        Figure(
                            label: Text(copy: "最近 \(recent.weeks) 周 · 人均", bundle: .module),
                            value: Text(
                                recent.daysPerMember,
                                format: .number.precision(.fractionLength(0...1)).locale(AppLanguage.current.locale))
                        )
                        .accessibilityIdentifier("squad.goal.recent")
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                if canChange {
                    HStack(spacing: Space.xxs) {
                        ForEach(Array(SquadWeeklyGoal.choices), id: \.self) { days in
                            PickPill(
                                Text(verbatim: "\(days)"), look: .onInk, isSelected: days == goal.nextDaysPerMember
                            ) {
                                pick(days)
                            }
                            .accessibilityLabel(Text(copy: "人均 \(days) 次", bundle: .module))
                            .accessibilityIdentifier("squad.goal.pick.\(days)")
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .inkCard()
            if canChange {
                Group {
                    if goal.nextDaysPerMember != goal.daysPerMember {
                        Text(copy: "下周起人均 \(goal.nextDaysPerMember) 次", bundle: .module)
                    } else {
                        Text(copy: "改动下周生效", bundle: .module)
                    }
                }
                .typeStyle(TypeRamp.footnote)
                .foregroundStyle(Color(role: .fgMuted, in: theme))
                .accessibilityIdentifier("squad.goal.note")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("squad.goal")
    }
}

/// One of the card's numbers: its label over the number in Barlow and 次.
private struct Figure: View {
    let label: Text
    let value: Text
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            label
                .typeStyle(TypeRamp.footnoteEmphasis)
                .foregroundStyle(Color(role: .fgOnInkMuted, in: theme))
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: Space.xxs) {
                value
                    .typeStyle(TypeRamp.scoreCard)
                    .foregroundStyle(Color(role: .fgOnBrand, in: theme))
                    .monospacedDigit()
                Text(copy: "次", bundle: .module)
                    .typeStyle(TypeRamp.footnoteEmphasis)
                    .foregroundStyle(Color(role: .fgOnInkMuted, in: theme))
            }
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
