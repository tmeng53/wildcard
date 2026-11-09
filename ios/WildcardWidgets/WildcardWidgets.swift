import DesignSystem
import DesignSystemUI
import HomeWidgetDomain
import HomeWidgetUI
import SwiftUI
import WidgetKit

/// The home screen widgets: 我的一周 (small) and 小队和教练 (medium, either side).
@main
struct WildcardWidgets: WidgetBundle {
    var body: some Widget {
        WeekHomeWidget()
        SquadHomeWidget()
    }
}

/// 我的一周: a tap opens 打卡 until I check in today, then 今天.
struct WeekHomeWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "week", intent: WeekIntent.self, provider: BoardProvider<WeekIntent>()
        ) { entry in
            WidgetFace(entry: entry) { board in
                WeekWidget(board: board)
                    .widgetURL(board.weekLink.url)
            }
        }
        .configurationDisplayName(WidgetCopy.weekName)
        .description(WidgetCopy.weekDescription)
        .supportedFamilies([.systemSmall])
    }
}

/// 小队和教练: the squad's side (a tap opens 今天, its 打卡 opens 打卡) or the coach's (a tap
/// opens its page, its button answers today's challenge in place), picked when it is edited.
struct SquadHomeWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "squad", intent: SquadOrCoachIntent.self, provider: BoardProvider<SquadOrCoachIntent>()
        ) { entry in
            WidgetFace(entry: entry) { board in
                switch entry.side {
                case .squad:
                    SquadWidget(board: board)
                        .widgetURL(WidgetLink.today.url)
                case .coach:
                    if let coach = board.coach {
                        CoachWidget(face: coach) { challenge in
                            ChallengeButton(challenge: challenge)
                        }
                        .widgetURL(WidgetLink.coach.url)
                    } else {
                        WidgetNotice(.noCoach)
                            .widgetURL(WidgetLink.today.url)
                    }
                }
            }
        }
        .configurationDisplayName(WidgetCopy.squadName)
        .description(WidgetCopy.squadDescription)
        .supportedFamilies([.systemMedium])
    }
}

/// 接受 or 完成 on the coach's side, each an App Intent the widget runs without opening the app.
private struct ChallengeButton: View {
    let challenge: CoachFace.Challenge

    var body: some View {
        switch challenge.step {
        case .open:
            Button(intent: AcceptChallengeIntent(squad: challenge.squad, note: challenge.note)) {
                ChallengeButtonLabel(step: challenge.step)
            }
            .buttonStyle(.plain)
        case .accepted, .done:
            Button(intent: CompleteChallengeIntent(squad: challenge.squad, note: challenge.note)) {
                ChallengeButtonLabel(step: challenge.step)
            }
            .buttonStyle(.plain)
        }
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
