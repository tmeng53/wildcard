import DesignSystem
import DesignSystemUI
import HealthDomain
import HomeWidgetDomain
import HomeWidgetUI
import SwiftUI
import WidgetKit

/// The home screen widgets: 我的一周 (small) and 小队今天 (medium).
@main
struct WildcardWidgets: WidgetBundle {
    var body: some Widget {
        WeekHomeWidget()
        SquadHomeWidget()
    }
}

/// 我的一周: a tap opens 打卡 until I check in today, then 今天; its capsule's 打卡 posts the
/// workout Health synced.
struct WeekHomeWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "week", intent: BoardIntent.self, provider: BoardProvider()) { entry in
            WidgetFace(entry: entry) { board in
                WeekWidget(board: board) { workout in PostWorkoutButton(workout: workout) }
                    .widgetURL(board.weekLink.url)
            }
        }
        .configurationDisplayName(WidgetCopy.weekName)
        .description(WidgetCopy.weekDescription)
        .supportedFamilies([.systemSmall])
    }
}

/// 小队今天: a tap opens 今天, and its 打卡 opens 打卡, or, while Health has a workout to post,
/// its capsule's 打卡 posts it.
struct SquadHomeWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "squad", intent: BoardIntent.self, provider: BoardProvider()) { entry in
            WidgetFace(entry: entry) { board in
                SquadWidget(board: board) { workout in PostWorkoutButton(workout: workout) }
                    .widgetURL(WidgetLink.today.url)
            }
        }
        .configurationDisplayName(WidgetCopy.squadName)
        .description(WidgetCopy.squadDescription)
        .supportedFamilies([.systemMedium])
    }
}

/// The capsule's 打卡: posts the workout in place, through `PostWorkoutIntent`.
private struct PostWorkoutButton: View {
    let workout: ImportedWorkout

    var body: some View {
        Button(intent: PostWorkoutIntent(workout: workout.id)) {
            PostWorkoutLabel()
        }
        .buttonStyle(.plain)
    }
}

/// A widget's face: the board, or why there is none, on the canvas white in the app's language.
private struct WidgetFace<Board: View>: View {
    let entry: BoardEntry
    @ViewBuilder let board: (WidgetBoard) -> Board

    var body: some View {
        Group {
            switch entry.state {
            case .board(let shown): board(shown)
            case .noSquad: WidgetNotice(.noSquad).widgetURL(WidgetLink.today.url)
            case .signedOut: WidgetNotice(.signedOut).widgetURL(WidgetLink.today.url)
            case .unavailable: WidgetNotice(.unavailable).widgetURL(WidgetLink.today.url)
            }
        }
        .environment(\.sceneTheme, .gym)
        .environment(\.locale, AppLanguage.current.locale)
        .containerBackground(for: .widget) { Color(role: .bgCanvas, in: .gym) }
    }
}
