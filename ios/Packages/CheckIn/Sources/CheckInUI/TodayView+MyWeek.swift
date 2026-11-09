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
    func myWeek(
        home: Home, day: LocalDay, week: WeekCount, challenge: WeekChallenge? = nil
    ) -> DesignSystemUI.MyWeek {
        let record = home.week(on: day)
        return DesignSystemUI.MyWeek(
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
            },
            challenge: challenge)
    }

    /// The challenge I accepted from the coach for today, under today's line (Tracy, 2026-11-08):
    /// what to do then how much (「拉伸 5 分钟」), and who set it.
    func weekChallenge(_ today: DayChallenge?, coach: CoachSpeaker?) -> WeekChallenge? {
        guard let today else { return nil }
        let challenge = today.challenge
        let amount = challenge.amount.map { amount in [String(amount), challenge.unit].compactMap(\.self) } ?? []
        let coach = coach?.name ?? ""
        return WeekChallenge(
            title: ([challenge.title] + amount).joined(separator: " "),
            byline: String(localized: "\(coach) · 今日挑战", bundle: .module.inAppLanguage),
            isDone: challenge.completedBy != nil)
    }

    /// A day's lines: each session I trained with its minutes, 请假了 or 休息日, else the plan's sport, light.
    func dayDetail(
        _ status: WeekRecord.Day, activity: Activity?, log: WeekRecord.DayLog, isToCome: Bool
    ) -> WeekDayDetail {
        let meals = isToCome ? nil : WeekDayDetail.Meals(healthy: log.healthyMeals, cheat: log.cheatMeals)
        switch status {
        case .trained:
            let lines = log.sessions.map { session in
                if let minutes = session.minutes {
                    String(localized: "\(session.activity.localizedName) \(minutes) 分钟", bundle: .module.inAppLanguage)
                } else {
                    session.activity.localizedName
                }
            }
            return WeekDayDetail(lines: lines, isPlan: false, meals: meals)
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
