#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import HealthDomain
import SportsUI
import SwiftUI

/// Today's Apple Health workouts, newest first: each its sport, minutes and start time. The one
/// picked is outlined, and tapping it again lets it go; one already posted shows 已发 and can't
/// be picked.
struct HealthChips: View {
    @Environment(\.sceneTheme) private var theme
    let model: ComposeModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            SectionLabel(Text(copy: "今天 Apple 健康里的运动", bundle: .module))
            ScrollView(.horizontal) {
                HStack(spacing: Space.xs) {
                    ForEach(model.healthWorkouts) { today in
                        chip(today)
                    }
                }
                .padding(.vertical, Space.xxs / 4)
            }
            .scrollIndicators(.hidden)
            .horizontalScrollFade()
        }
    }

    private func chip(_ today: TodaysWorkout) -> some View {
        let imported = today.imported
        let isPicked = model.workout?.source == imported.workout.source
        return Button {
            model.pick(imported)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Space.xxs) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: Self.heart))
                        .foregroundStyle(Color(role: .fgDanger, in: theme))
                    (imported.activity?.name ?? Text(copy: "运动", bundle: .module))
                    if let minutes = imported.minutes {
                        Text(copy: "\(minutes.value) 分钟", bundle: .module)
                    }
                }
                .typeStyle(TypeRamp.calloutEmphasis)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                Group {
                    if today.isPosted {
                        Text(copy: "已发", bundle: .module)
                    } else {
                        Text(imported.workout.startedAt.date, format: .dateTime.hour().minute())
                    }
                }
                .typeStyle(TypeRamp.caption)
                .foregroundStyle(Color(role: .fgMuted, in: theme))
            }
            .lineLimit(1)
            .padding(.horizontal, Space.s)
            .frame(height: Self.height, alignment: .leading)
            .background(
                Color(role: .bgCanvas, in: theme), in: RoundedRectangle(cornerRadius: Radius.pick, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Radius.pick, style: .continuous)
                    .strokeBorder(
                        Color(role: isPicked ? .fgDefault : .borderDefault, in: theme),
                        lineWidth: isPicked ? Sizing.selectionStroke : 1)
            }
            .opacity(today.isPosted ? 0.5 : 1)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(today.isPosted)
        .haptic(.pick, trigger: isPicked)
        .accessibilityAddTraits(isPicked ? .isSelected : [])
        .accessibilityIdentifier("compose.health.\(imported.workout.source.id)")
    }

    private static let height: Double = 48
    private static let heart: Double = 11
}

/// A workout's numbers in place of the minutes: 「成绩 · ♥ Apple 健康」 over the 成绩条, where a
/// tap strikes a number out of the post and another brings it back.
struct ScoreRow: View {
    @Environment(\.sceneTheme) private var theme
    let model: ComposeModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            HStack(spacing: Space.xs) {
                SectionLabel(Text(copy: "成绩", bundle: .module))
                HStack(spacing: Space.xxs / 2) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: Self.heart))
                        .foregroundStyle(Color(role: .fgDanger, in: theme))
                    Text(copy: "Apple 健康", bundle: .module)
                }
                .typeStyle(TypeRamp.label)
                .foregroundStyle(Color(role: .fgMuted, in: theme))
                .padding(.horizontal, Space.xs)
                .padding(.vertical, Space.xxs / 4)
                .background(Color(role: .bgSubtle, in: theme), in: Capsule())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(copy: "Apple 健康", bundle: .module))
                Spacer(minLength: 0)
                Text(copy: "点一格可以不发", bundle: .module)
                    .typeStyle(TypeRamp.label)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
            }
            ScoreStrip(cells: model.scoreCells, activity: model.currentActivity, struck: model.struck) { cell in
                model.toggle(cell)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .accessibilityIdentifier("compose.score")
    }

    private static let heart: Double = 10
}
#endif
