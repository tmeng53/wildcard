#if os(iOS)
import DesignSystem
import DesignSystemUI
import SwiftUI

/// The full-width card at the top of 今天 (spec rev 186): the week and scene, the squad's
/// name, 本周小队训练 x/y 次 with its bar (planned training days, not people), and how many trained today. No personal count, no goal
/// wording, no buttons.
struct TopCard: View {
    @Environment(\.sceneTheme) private var theme
    let board: TodayBoard

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: 0) {
                Text("第 \(board.weekNumber) 周", bundle: .module)
                Text(verbatim: " · ")
                board.scene.name
            }
            .typeStyle(TypeRamp.footnote)
            .foregroundStyle(Color(role: .signatureText, in: theme))
            .padding(.horizontal, Space.xs)
            .padding(.vertical, Space.xxs)
            .background(Color(role: .signatureWash, in: theme), in: Capsule())

            Text(verbatim: board.squadName)
                .typeStyle(TypeRamp.headline)
                .foregroundStyle(Color(role: .textPrimary, in: theme))

            HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                Text("本周小队训练", bundle: .module)
                    .typeStyle(TypeRamp.callout)
                    .foregroundStyle(Color(role: .textSecondary, in: theme))
                Score(
                    count: board.progress.done, goal: board.progress.goal, countStyle: TypeRamp.scoreLarge,
                    goalStyle: TypeRamp.scoreLargeDenominator
                )
                .contentTransition(.numericText(value: Double(board.progress.done)))
                Text("次", bundle: .module)
                    .typeStyle(TypeRamp.callout)
                    .foregroundStyle(Color(role: .textSecondary, in: theme))
            }
            ProgressBar(fraction: board.progress.fraction)
            Text("今天 \(board.trainedToday) 人练了", bundle: .module)
                .typeStyle(TypeRamp.callout)
                .foregroundStyle(Color(role: .textPrimary, in: theme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.m)
        .frosted(white: Frost.bannerFill, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today.card")
    }
}
#endif
