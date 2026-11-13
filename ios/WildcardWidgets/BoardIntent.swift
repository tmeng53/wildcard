import AppIntents
import WidgetKit

/// What a widget is set to show, from 长按 › 编辑小组件 › 显示: its progress (我的一周 or 小队今天) or
/// 本周出赛表. Both widgets keep the one intent type, named `BoardIntent`, that they were placed
/// with before they had anything to set: WidgetKit stores a placed widget's configuration under
/// its intent type's name, and a widget whose stored type no longer exists stays on its
/// placeholder forever after an update. So never rename this type or give a widget another one;
/// add a parameter with a default instead, which a stored configuration without it reads.
struct BoardIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "外卡"
    static let description = IntentDescription("显示内容")

    @Parameter(title: "显示", default: .progress) var shows: BoardShows

    var showsSchedule: Bool { shows == .schedule }
}

/// What either widget can show.
enum BoardShows: String, AppEnum {
    case progress
    case schedule

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "显示"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .progress: "进度",
        .schedule: "本周出赛表",
    ]
}
