#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import ScheduleDomain
import SportsUI
import SwiftUI

/// The counts under this week: lifetime trained days, and the squad's this week.
struct ScheduleCounts: View {
    let store: ScheduleStore
    let sheet: WeekSheet

    var body: some View {
        HStack(alignment: .top, spacing: Space.cardGap) {
            CountCard(
                label: Text("一共练了", bundle: .module), count: store.lifetimeTrainedDays ?? 0, goal: nil,
                unit: Text("天", bundle: .module)
            )
            .accessibilityIdentifier("schedule.count.lifetime")
            if let squad = sheet.squad {
                CountCard(
                    label: Text("本周小队训练", bundle: .module), count: squad.trained, goal: squad.planned,
                    unit: Text("次", bundle: .module)
                )
                .accessibilityIdentifier("schedule.count.squad")
            }
        }
    }
}

/// Under a past week: each title the week's awards gave the member, with its 颁奖词. The poster
/// carries the stickers; their words sit here, clear of the lanes.
struct WeekAwards: View {
    let titles: [AwardTitle]
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Space.cardGap) {
            ForEach(Array(titles.enumerated()), id: \.element) { position, title in
                VStack(alignment: .leading, spacing: Space.labelGap) {
                    Label {
                        Text(verbatim: title.title)
                            .typeStyle(TypeRamp.headline)
                            .foregroundStyle(Color(role: .fgDefault, in: theme))
                    } icon: {
                        Image(systemName: "star.fill")
                            .font(.system(size: Sizing.smallIcon, weight: .semibold))
                            .foregroundStyle(Color(role: .fgAccent, in: theme))
                    }
                    Text(verbatim: title.speech)
                        .typeStyle(TypeRamp.body)
                        .foregroundStyle(Color(role: .fgDefault, in: theme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(on: .page)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("schedule.award.\(position)")
            }
        }
    }
}

/// The picks for the day in hand: the week's sports and the usual ones, 休息, and 更多.
struct DayPicks: View {
    let store: ScheduleStore
    let sheet: WeekSheet
    let index: Int
    let onPick: (Activity) -> Void
    let onRest: () -> Void
    let onMore: () -> Void

    var body: some View {
        let day = sheet.weekStart.adding(days: index)
        let plan = sheet.plan[index]
        let picks = store.suggestedActivities(common: SportList.shared.catalog.checkInQuick)
        VStack(alignment: .leading, spacing: Space.labelGap) {
            SectionLabel(
                Text("\(ScheduleLabels.weekday(day)) · \(ScheduleLabels.shortDate(day))", bundle: .module))
            FlowRow {
                ForEach(picks, id: \.key) { activity in
                    PickPill(activity.name, systemImage: activity.symbol, isSelected: plan == .train(activity)) {
                        onPick(activity)
                    }
                    .accessibilityIdentifier("schedule.pick.\(activity.key)")
                }
                PickPill(Text("休息", bundle: .module), systemImage: "moon", isSelected: plan == .rest) {
                    onRest()
                }
                .accessibilityIdentifier("schedule.pick.rest")
                PickPill(Text("更多", bundle: .module), systemImage: "magnifyingglass", isSelected: false) {
                    onMore()
                }
                .accessibilityIdentifier("schedule.pick.more")
            }
        }
    }
}

/// 存图's picture couldn't be drawn, for a moment, under the top bar where the member just
/// tapped.
struct SaveNote: View {
    let saving: ScheduleModel.Saving
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        switch saving {
        case .failed:
            Text("没存上，再试一次", bundle: .module)
                .noteStyle(theme)
        default:
            EmptyView()
        }
    }
}

/// Why the last change to the week didn't go through, under the panel it came from.
struct PanelNote: View {
    let store: ScheduleStore
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        if let failure = store.failure {
            ScheduleLabels.failure(failure)
                .noteStyle(theme)
                .accessibilityIdentifier("schedule.failure")
        }
    }
}

/// A label over a number and its unit, on a grey card: 一共练了 46 天, 本周小队训练 14/22 次.
struct CountCard: View {
    let label: Text
    let count: Int
    let goal: Int?
    let unit: Text
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Space.labelGap) {
            SectionLabel(label)
            HStack(alignment: .firstTextBaseline, spacing: Space.xxs) {
                Score(count: count, goal: goal, size: .card)
                unit
                    .typeStyle(TypeRamp.footnote)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(on: .page)
        .accessibilityElement(children: .combine)
    }
}

/// Next week: how long until it starts, ticking every second, and the Monday it starts on.
struct CountdownCard: View {
    let store: ScheduleStore
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: Space.labelGap) {
                    SectionLabel(Text("离开赛还有", bundle: .module))
                    if let left = store.untilNextWeek {
                        HStack(alignment: .firstTextBaseline, spacing: Space.xxs) {
                            Score(count: left.days, size: .card)
                            Text("天", bundle: .module)
                                .typeStyle(TypeRamp.footnote)
                                .foregroundStyle(Color(role: .fgMuted, in: theme))
                            Text(
                                verbatim: String(format: "%02d:%02d:%02d", left.hours, left.minutes, left.seconds)
                            )
                            .typeStyle(TypeRamp.scoreCard)
                            .monospacedDigit()
                            .foregroundStyle(Color(role: .fgDefault, in: theme))
                            .padding(.leading, Space.xs - 2)
                        }
                    }
                }
                Spacer(minLength: Space.xs)
                if let start = store.shownWeek {
                    Text("周一 \(ScheduleLabels.posterDate(start))", bundle: .module)
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(on: .page)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("schedule.countdown")
    }
}

extension View {
    /// A short note under the poster: what just happened.
    fileprivate func noteStyle(_ theme: SceneTheme) -> some View {
        typeStyle(TypeRamp.footnote)
            .foregroundStyle(Color(role: .fgMuted, in: theme))
    }
}
#endif
