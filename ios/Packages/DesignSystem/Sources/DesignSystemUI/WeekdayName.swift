#if canImport(SwiftUI)
import SwiftUI

/// A weekday's name, Monday first (0 for Monday): 周一 for a line, 一 under a day's circle.
public enum WeekdayName {
    /// 周一 to 周日.
    public static func full(_ weekday: Int) -> Text {
        switch weekday {
        case 0: Text(copy: "周一", bundle: .module)
        case 1: Text(copy: "周二", bundle: .module)
        case 2: Text(copy: "周三", bundle: .module)
        case 3: Text(copy: "周四", bundle: .module)
        case 4: Text(copy: "周五", bundle: .module)
        case 5: Text(copy: "周六", bundle: .module)
        default: Text(copy: "周日", bundle: .module)
        }
    }

    /// 一 to 日.
    public static func short(_ weekday: Int) -> Text {
        switch weekday {
        case 0: Text(copy: "一", bundle: .module)
        case 1: Text(copy: "二", bundle: .module)
        case 2: Text(copy: "三", bundle: .module)
        case 3: Text(copy: "四", bundle: .module)
        case 4: Text(copy: "五", bundle: .module)
        case 5: Text(copy: "六", bundle: .module)
        default: Text(copy: "日", bundle: .module)
        }
    }
}
#endif
