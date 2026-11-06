#if os(iOS)
import CheckInDomain
import Contracts
import DesignSystemUI
import SportsUI
import SwiftUI

extension TodayView {
    /// My week for the card's second page: this week's days, what I trained, and each day's line
    /// (what I trained or the plan's sport, and my meals up to today), with the count the squad's
    /// today carries.
    func myWeek(home: Home, day: LocalDay, week: WeekCount) -> DesignSystemUI.MyWeek {
        let record = home.week(on: day)
        return DesignSystemUI.MyWeek(
            summary: record.trained.map {
                String(localized: "\($0.activity.localizedName) \($0.days)", bundle: .module.inAppLanguage)
            }
            .joined(separator: " · "),
            done: week.trainedDays, planned: week.plannedDays,
            days: zip(record.days, record.activities).map { status, activity in
                switch status {
                case .trained: .trained(symbol: activity?.symbol)
                case .disclaimer: .excused
                case .restDay: .restDay
                // A training day without a sport gets a generic icon.
                case .open: .planned(symbol: activity?.symbol ?? "figure.run")
                }
            },
            today: record.today,
            details: record.days.indices.map { index in
                dayDetail(
                    record.days[index], activity: record.activities[index], log: record.logs[index],
                    isToCome: index > record.today)
            })
    }

    /// A day's line: what I trained with its minutes, 请假了 or 休息日, else the plan's sport, light.
    func dayDetail(
        _ status: WeekRecord.Day, activity: Activity?, log: WeekRecord.DayLog, isToCome: Bool
    ) -> WeekDayDetail {
        let meals = isToCome ? nil : WeekDayDetail.Meals(healthy: log.healthyMeals, cheat: log.cheatMeals)
        switch status {
        case .trained:
            let line = log.sessions.map { session in
                if let minutes = session.minutes {
                    String(localized: "\(session.activity.localizedName) \(minutes) 分钟", bundle: .module.inAppLanguage)
                } else {
                    session.activity.localizedName
                }
            }
            return WeekDayDetail(line: line.joined(separator: " · "), isPlan: false, meals: meals)
        case .disclaimer:
            return WeekDayDetail(
                line: String(localized: "请假了", bundle: .module.inAppLanguage), isPlan: false, meals: meals)
        case .restDay:
            return WeekDayDetail(
                line: String(localized: "休息日", bundle: .module.inAppLanguage), isPlan: false, meals: meals)
        case .open:
            return WeekDayDetail(
                line: activity?.localizedName ?? String(localized: "训练日", bundle: .module.inAppLanguage), isPlan: true,
                meals: meals)
        }
    }
}
#endif
