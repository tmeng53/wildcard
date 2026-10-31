import Contracts
import Foundation

/// One week of the 出赛表 as the server holds it: the plan, how each day went, the titles the
/// squad's weekly awards gave the member, the squad's count and the week's 饮食小目标.
public struct WeekSheet: Hashable, Sendable {
    /// The week's Monday.
    public let weekStart: LocalDay
    /// Seven days, Monday first.
    public var plan: [PlanDay]
    /// Seven days, Monday first: what the member checked in each day.
    public let marks: [DayMark]
    /// The titles (头衔) the week's awards gave the member, best first. Empty until the awards
    /// are written on Sunday night, and for a week they didn't check in.
    public let titles: [AwardTitle]
    /// The squad's 练了 against everyone's plans; nil when the member is in no squad.
    public let squad: SquadCount?
    /// At most `FuelGoal.maxCount`, in the order picked.
    public var fuel: [FuelGoal]

    public init(
        weekStart: LocalDay, plan: [PlanDay], marks: [DayMark], titles: [AwardTitle] = [], squad: SquadCount? = nil,
        fuel: [FuelGoal] = []
    ) throws(ScheduleError) {
        guard plan.count == WeeklyPlan.dayCount, marks.count == WeeklyPlan.dayCount else { throw .refused }
        guard fuel.count <= FuelGoal.maxCount else { throw .refused }
        self.weekStart = weekStart
        self.plan = plan
        self.marks = marks
        self.titles = titles
        self.squad = squad
        self.fuel = fuel
    }

    /// The days the plan trains.
    public var plannedDays: Int { plan.count { $0 != .rest } }

    /// The days with a 练了, planned or not: what 本周 x/y counts, as the home's my week does.
    public var trainedDays: Int { marks.count { $0 == .trained } }
}

/// How a day went: one status a day, a 练了 over a 请假条.
public enum DayMark: Hashable, Sendable {
    case trained
    case disclaimer
    case none
}

/// A title (头衔) the weekly awards gave the member, and its award line (颁奖词).
public struct AwardTitle: Hashable, Sendable {
    public let title: String
    public let speech: String

    public init(title: String, speech: String) {
        (self.title, self.speech) = (title, speech)
    }
}

/// The squad's week: days its members trained against the days their plans train.
public struct SquadCount: Hashable, Sendable {
    public let trained: Int
    public let planned: Int

    public init(trained: Int, planned: Int) {
        (self.trained, self.planned) = (trained, planned)
    }
}

/// A 饮食小目标 for the week: one of the suggestions, or the member's own words. Habits only,
/// never a body number, a calorie or a macro.
public enum FuelGoal: Hashable, Sendable {
    /// How many goals a week holds.
    public static let maxCount = 3
    /// Characters a goal of the member's own may have, counted as people see them.
    public static let maxLength = 8

    case suggested(FuelSuggestion)
    case own(String)

    /// The member's own goal, trimmed: one line of 1 to `maxLength` characters.
    public static func own(typed text: String) throws(ScheduleError) -> FuelGoal {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxLength, !trimmed.contains(where: \.isNewline) else {
            throw .invalidFuelGoal
        }
        return .own(trimmed)
    }
}

/// The 饮食小目标 the picker suggests. Their words live in the String Catalog, by raw value.
public enum FuelSuggestion: String, CaseIterable, Hashable, Sendable {
    /// 喝够水
    case water
    /// 自己做饭
    case cookAtHome
    /// 每天有菜
    case veggies
    /// 奶茶减半
    case lessBubbleTea
    /// 好好吃早餐
    case breakfast
    /// 晚饭早点吃
    case earlyDinner
}
