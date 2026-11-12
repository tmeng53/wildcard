import AppIntents
import WidgetKit

/// What a widget is set to show, from 长按 › 编辑小组件 › 显示: what it was made for, or 本周出赛表.
protocol BoardIntent: WidgetConfigurationIntent {
    var showsSchedule: Bool { get }
}

/// The small widget: 我的一周 unless set to 本周出赛表.
struct WeekIntent: BoardIntent {
    static let title: LocalizedStringResource = "外卡"
    static let description = IntentDescription("选这个小组件显示什么")

    @Parameter(title: "显示", default: .week) var shows: WeekShows

    var showsSchedule: Bool { shows == .schedule }
}

/// The medium widget: 小队今天 unless set to 本周出赛表.
struct SquadIntent: BoardIntent {
    static let title: LocalizedStringResource = "外卡"
    static let description = IntentDescription("选这个小组件显示什么")

    @Parameter(title: "显示", default: .squad) var shows: SquadShows

    var showsSchedule: Bool { shows == .schedule }
}

/// What the small widget can show.
enum WeekShows: String, AppEnum {
    case week
    case schedule

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "显示"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .week: "我的一周",
        .schedule: "本周出赛表",
    ]
}

/// What the medium widget can show.
enum SquadShows: String, AppEnum {
    case squad
    case schedule

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "显示"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .squad: "小队今天",
        .schedule: "本周出赛表",
    ]
}
