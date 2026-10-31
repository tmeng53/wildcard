import Contracts
import Foundation
import ScheduleDomain

/// A member in memory, for previews, UI tests and the sample squad: weeks back to the
/// one they joined, each with a plan, the days they trained and, once over, their titles.
public actor InMemoryScheduleBackend: ScheduleBackend {
    private let member: ScheduleProfile
    private let thisWeek: LocalDay
    private let today: LocalDay
    private var sheets: [LocalDay: WeekSheet] = [:]
    private var lifetime: Int

    public init(profile: ScheduleProfile, today: LocalDay, sheets: [WeekSheet], lifetimeTrainedDays: Int) {
        member = profile
        self.today = today
        thisWeek = today.weekStart
        lifetime = lifetimeTrainedDays
        for sheet in sheets { self.sheets[sheet.weekStart] = sheet }
    }

    /// Tracy, who joined five weeks ago: most planned days trained, now and then a 请假条 or a
    /// day missed, today trained, and a title or more for each week that is over.
    public static func sample(now: Date, timeZone: TimeZone = .current) -> InMemoryScheduleBackend {
        let today = LocalDay(at: now, in: timeZone)
        let thisWeek = today.weekStart
        let firstWeek = thisWeek.adding(days: -7 * 5)
        let sheets = (-5...1).compactMap { offset -> WeekSheet? in
            let weekStart = thisWeek.adding(days: 7 * offset)
            let plan = offset.isMultiple(of: 2) ? planA : planB
            let marks = (0..<WeeklyPlan.dayCount).map { index -> DayMark in
                let day = weekStart.adding(days: index)
                guard day <= today, plan[index] != .rest else { return .none }
                if day == today { return .trained }
                // Most planned days trained; now and then a 请假条 or a day missed.
                switch (index + offset * 3 + 21) % 7 {
                case 1: return .disclaimer
                case 4: return .none
                default: return .trained
                }
            }
            let titles = offset < 0 ? Array(sampleTitles.shuffledBy(seed: offset).prefix(1 + (-offset % 3))) : []
            let squad = offset <= 0 ? SquadCount(trained: 14 + (offset * 5 + 40) % 7, planned: 22) : nil
            let fuel: [FuelGoal] = offset < 1 ? [.suggested(.water), .suggested(.cookAtHome)] : [.suggested(.water)]
            return try? WeekSheet(
                weekStart: weekStart, plan: plan, marks: marks, titles: titles, squad: squad, fuel: fuel)
        }
        return InMemoryScheduleBackend(
            profile: ScheduleProfile(nickname: "Tracy", timeZone: timeZone, firstWeek: firstWeek), today: today,
            sheets: sheets, lifetimeTrainedDays: 46)
    }

    private static let planA: [PlanDay] = [
        .train(.sport("run")), .train(.sport("tennis")), .rest, .train(.sport("strength")), .train(.sport("run")),
        .rest,
        .train(.sport("tennis")),
    ]
    private static let planB: [PlanDay] = [
        .train(.sport("run")), .rest, .train(.sport("strength")), .train(.sport("tennis")), .rest,
        .train(.sport("swim")),
        .train(.sport("run")),
    ]

    /// What the weekly awards might say; the real ones come from the API.
    private static let sampleTitles = [
        AwardTitle(title: "网球担当", speech: "三次站上网球场，打到天黑还不走"),
        AwardTitle(title: "雨天也出门", speech: "周四下着雨，照样跑完了五公里"),
        AwardTitle(title: "说练就练", speech: "计划写了四天，就练了四天"),
        AwardTitle(title: "小队气氛组", speech: "谁练完你都第一个冲出来夸"),
        AwardTitle(title: "早起冠军", speech: "三次在早上七点前打卡"),
    ]

    public func profile() async throws(ScheduleError) -> ScheduleProfile { member }

    public func week(starting weekStart: LocalDay) async throws(ScheduleError) -> WeekSheet {
        if let sheet = sheets[weekStart] { return sheet }
        // A week further ahead follows the latest plan, as the API's does.
        let latest = sheets.keys.filter { $0 < weekStart }.max().flatMap { sheets[$0]?.plan } ?? Self.planA
        return try WeekSheet(weekStart: weekStart, plan: latest, marks: Array(repeating: .none, count: 7))
    }

    public func savePlan(_ days: [PlanDay], weekStart: LocalDay) async throws(ScheduleError) -> [PlanDay] {
        guard weekStart >= thisWeek else { throw .weekOver }
        var sheet = try await week(starting: weekStart)
        if weekStart == thisWeek {
            let before = sheet.plan
            // Days before today stay as they were; a training today stays a training day, and a
            // rest today may become one. Later days change freely.
            let todayIndex = today.weekday - 1
            guard days.count == before.count, days.prefix(todayIndex) == before.prefix(todayIndex),
                before[todayIndex] == .rest || days[todayIndex] != .rest
            else { throw .dayStarted }
        }
        sheet.plan = days
        sheets[weekStart] = sheet
        return days
    }

    public func saveFuel(_ goals: [FuelGoal], weekStart: LocalDay) async throws(ScheduleError) {
        guard weekStart >= thisWeek else { throw .weekOver }
        var sheet = try await week(starting: weekStart)
        sheet.fuel = goals
        sheets[weekStart] = sheet
    }

    public func trainedDays() async throws(ScheduleError) -> Int { lifetime }
}

extension Array {
    /// The same order for the same seed, so the sample looks the same on every launch.
    fileprivate func shuffledBy(seed: Int) -> [Element] {
        guard !isEmpty else { return self }
        let start = ((seed % count) + count) % count
        return Array(self[start...] + self[..<start])
    }
}
