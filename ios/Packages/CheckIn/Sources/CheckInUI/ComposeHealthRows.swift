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
            SectionLabel(Text("检测到的运动", bundle: .module))
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
                    (imported.activity?.name ?? Text("运动", bundle: .module))
                    if let minutes = imported.minutes {
                        Text("\(minutes.value) 分钟", bundle: .module)
                    }
                }
                .typeStyle(TypeRamp.calloutEmphasis)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                Group {
                    if today.isPosted {
                        Text("已发", bundle: .module)
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

/// A workout's numbers in place of the minutes, a cell each: a tap strikes one out of the post
/// (dashed and crossed through) and another brings it back.
struct ScoreRow: View {
    @Environment(\.sceneTheme) private var theme
    let model: ComposeModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            SectionLabel(Text("数据", bundle: .module))
            ScrollView(.horizontal) {
                HStack(spacing: Space.xs) {
                    ForEach(model.scoreCells) { cell in
                        scoreCell(cell)
                    }
                }
                .padding(.vertical, Space.xxs / 4)
            }
            .scrollIndicators(.hidden)
            .horizontalScrollFade()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("compose.score")
    }

    private func scoreCell(_ cell: ScoreCell) -> some View {
        let isStruck = model.struck.contains(cell.cell)
        let shape = RoundedRectangle(cornerRadius: Radius.ticket, style: .continuous)
        return Button {
            model.toggle(cell.cell)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: Space.xxs / 2) {
                    Text(verbatim: cell.value)
                        .typeStyle(TypeRamp.scoreInline)
                        .strikethrough(isStruck)
                    if let unit = cell.unit {
                        unit.text.typeStyle(TypeRamp.label)
                    }
                }
                .foregroundStyle(Color(role: isStruck ? .fgSubtle : .fgDefault, in: theme))
                cell.label.text
                    .typeStyle(TypeRamp.caption)
                    .foregroundStyle(Color(role: isStruck ? .fgSubtle : .fgMuted, in: theme))
            }
            .lineLimit(1)
            .padding(.horizontal, Space.s)
            .frame(height: Self.height)
            .background(Color(role: .bgCanvas, in: theme), in: shape)
            .overlay {
                shape.strokeBorder(
                    Color(role: .borderDefault, in: theme),
                    style: StrokeStyle(lineWidth: 1, dash: isStruck ? [4, 3] : []))
            }
            .contentShape(shape)
        }
        .buttonStyle(PressableButtonStyle())
        .haptic(.pick, trigger: isStruck)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isStruck ? Text("不发", bundle: .module) : Text("发", bundle: .module))
        .accessibilityHint(isStruck ? Text("点一下恢复", bundle: .module) : Text("点一下划掉", bundle: .module))
        .accessibilityIdentifier("strip.\(cell.cell.rawValue)")
    }

    private static let height: Double = 56
}
#endif
