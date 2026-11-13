import DesignSystem
import DesignSystemUI
import HomeWidgetDomain
import HomeWidgetUI
import SwiftUI
import WidgetKit

/// The home screen widgets: 我的一周 (small) and 小队今天 (medium), either set to show 本周出赛表
/// instead from 编辑小组件.
@main
struct WildcardWidgets: WidgetBundle {
    var body: some Widget {
        WeekHomeWidget()
        SquadHomeWidget()
    }
}

/// 我的一周: a tap opens the 训练 page started from the workout Health synced while its capsule
/// offers one, else 打卡 until I check in today, then 今天. Set to 本周出赛表, a tap opens 出赛表.
struct WeekHomeWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "week", intent: BoardIntent.self, provider: BoardProvider()) { entry in
            WidgetFace(entry: entry) { board in
                if entry.showsSchedule {
                    ScheduleWidget(board: board, size: .small)
                        .widgetURL(WidgetLink.schedule.url)
                } else {
                    WeekWidget(board: board)
                        .widgetURL(board.weekLink.url)
                }
            }
        }
        // 本周出赛表 fills the widget edge to edge; the others keep the system's margins themselves.
        .contentMarginsDisabled()
        .configurationDisplayName(WidgetCopy.weekName)
        .description(WidgetCopy.weekDescription)
        .supportedFamilies([.systemSmall])
    }
}

/// 小队今天: a tap opens 今天, and its 打卡 opens 打卡, or, while Health has a workout to post,
/// its capsule's 打卡 opens the 训练 page started from it. Set to 本周出赛表, a tap opens 出赛表.
struct SquadHomeWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "squad", intent: BoardIntent.self, provider: BoardProvider()) { entry in
            WidgetFace(entry: entry) { board in
                if entry.showsSchedule {
                    ScheduleWidget(board: board, size: .medium)
                        .widgetURL(WidgetLink.schedule.url)
                } else {
                    SquadWidget(board: board)
                        .widgetURL(WidgetLink.today.url)
                }
            }
        }
        .contentMarginsDisabled()
        .configurationDisplayName(WidgetCopy.squadName)
        .description(WidgetCopy.squadDescription)
        .supportedFamilies([.systemMedium])
    }
}

/// A widget's face: the board, or why there is none, in the app's language: 本周出赛表 edge to
/// edge on its scene's grid, everything else inside the system's margins on the canvas white.
private struct WidgetFace<Board: View>: View {
    let entry: BoardEntry
    @ViewBuilder let board: (WidgetBoard) -> Board
    @Environment(\.widgetContentMargins) private var margins

    var body: some View {
        Group {
            switch entry.state {
            case .board(let shown) where entry.showsSchedule:
                board(shown)
                    .environment(\.sceneTheme, ScheduleWidget.scene(of: shown))
                    .containerBackground(for: .widget) {
                        ScheduleWidget.Backdrop().environment(\.sceneTheme, ScheduleWidget.scene(of: shown))
                    }
            case .board(let shown): canvas(board(shown))
            case .noSquad: canvas(WidgetNotice(.noSquad).widgetURL(WidgetLink.today.url))
            case .signedOut: canvas(WidgetNotice(.signedOut).widgetURL(WidgetLink.today.url))
            case .unavailable: canvas(WidgetNotice(.unavailable).widgetURL(WidgetLink.today.url))
            }
        }
        .environment(\.locale, AppLanguage.current.locale)
    }

    private func canvas(_ content: some View) -> some View {
        content
            .padding(margins)
            .environment(\.sceneTheme, .gym)
            .containerBackground(for: .widget) { Color(role: .bgCanvas, in: .gym) }
    }
}
