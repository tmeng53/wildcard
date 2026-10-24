import ScheduleDomain

#if os(iOS)
import Contracts
import SportsUI
import SwiftUI

/// The words and symbols the 出赛表 shows, all through this package's String Catalog.
enum ScheduleLabels {
    /// 周一 to 周日, Monday first.
    static func weekday(_ day: LocalDay) -> Text {
        let keys: [LocalizedStringKey] = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
        return Text(keys[day.weekday - 1], bundle: .module)
    }

    /// 10.13 – 10.19: month and day, the way Chinese posters write dates.
    static func dates(_ first: LocalDay, _ last: LocalDay) -> String {
        "\(posterDate(first)) – \(posterDate(last))"
    }

    /// 10.20, as the poster and the countdown write a day.
    static func posterDate(_ day: LocalDay) -> String {
        "\(day.month).\(day.day)"
    }

    /// 10/24, under a day's picks.
    static func shortDate(_ day: LocalDay) -> String {
        "\(day.month)/\(day.day)"
    }

    /// W3, the week the member joined being W1.
    static func week(_ number: Int) -> String {
        "W\(number)"
    }

    /// A lane's sport, or 休息; a training day with no sport set says 训练.
    static func plan(_ day: PlanDay) -> Text {
        switch day {
        case .rest: Text("休息", bundle: .module)
        case .train(let activity?): activity.name
        case .train(nil): Text("训练", bundle: .module)
        }
    }

    static func planName(_ day: PlanDay) -> String {
        switch day {
        case .rest: String(localized: "休息", bundle: .module)
        case .train(let activity?): activity.localizedName
        case .train(nil): String(localized: "训练", bundle: .module)
        }
    }

    static func fuel(_ goal: FuelGoal) -> Text {
        switch goal {
        case .suggested(let suggestion): Text(LocalizedStringKey(suggestion.key), bundle: .module)
        case .own(let text): Text(verbatim: text)
        }
    }

    static func fuelName(_ goal: FuelGoal) -> String {
        switch goal {
        case .suggested(let suggestion): Bundle.module.localizedString(forKey: suggestion.key, value: nil, table: nil)
        case .own(let text): text
        }
    }

    /// What went wrong saving, in friendly words; never a warning.
    static func failure(_ error: ScheduleError) -> Text {
        switch error {
        case .notSent: Text("网不太好，没存上，等下再改一次", bundle: .module)
        case .signedOut: Text("登录过期了，重新登录再来排", bundle: .module)
        case .weekOver: Text("这周已经结束了，就让它留在这儿吧", bundle: .module)
        case .dayStarted: Text("已经开始的日子改不了啦", bundle: .module)
        case .restDaysFixed: Text("这周的休息天数定好了，只能挪", bundle: .module)
        case .invalidFuelGoal: Text("小目标写 1 到 8 个字就好", bundle: .module)
        case .refused: Text("没存上，换个排法试试", bundle: .module)
        }
    }
}
#endif

extension FuelSuggestion {
    /// The String Catalog key for the words people see.
    var key: String { "fuel.\(rawValue)" }
}
