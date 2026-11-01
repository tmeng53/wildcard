import Contracts

/// The member's typical week, their 每周模板, drawn on sign-up's poster: what each day is, a
/// sport picked in the step before, a training day with no sport named, or 休息. This week and
/// every later one follow it until it is changed (this week counting only from the day the
/// member joined), so every day can change here, those already over this week too. Tapping a
/// day selects it, and picking what it is moves on to the next day, so a whole week takes a few
/// taps.
public struct WeekDraft: Hashable, Sendable {
    public private(set) var days: [PlanDay]
    /// The day the choices below the poster are for, from 0 (Monday).
    public private(set) var selected: Int
    /// What a day can be: each sport picked, or one training day with no sport if none was
    /// picked, then 休息.
    public let choices: [PlanDay]

    /// The training days for each number of them, spread out over the week; five rest on
    /// Wednesday and Sunday, as the approved design shows.
    static let trainingDays: [[Int]] = [[2], [1, 3], [0, 2, 4], [0, 1, 3, 4], [0, 1, 3, 4, 5]]

    /// One training day for each sport picked, at most five, in the order picked; a training
    /// day with no sport named if none was. Monday starts selected.
    public init(sports: [Activity]) {
        let trainings: [PlanDay] = sports.isEmpty ? [.train(nil)] : sports.map { .train($0) }
        let planned = Self.trainingDays[min(trainings.count, Self.trainingDays.count) - 1]
        days = (0..<WeeklyPlan.dayCount).map { index in
            planned.firstIndex(of: index).map { trainings[$0] } ?? .rest
        }
        selected = 0
        choices = trainings + [.rest]
    }

    public mutating func select(_ index: Int) {
        guard days.indices.contains(index) else { return }
        selected = index
    }

    /// Sets the selected day, then selects the next day, back to Monday after Sunday.
    /// True when a rest day became a training day, which the character hops for.
    @discardableResult
    public mutating func set(_ day: PlanDay) -> Bool {
        let becameTraining = days[selected] == .rest && day != .rest
        days[selected] = day
        selected = (selected + 1) % WeeklyPlan.dayCount
        return becameTraining
    }

    /// 每周训练 N/7 天: the week's training days.
    public var trainingDays: Int {
        days.count { $0 != .rest }
    }

    /// The training days from `day` (0 is Monday) to Sunday: what the week the member joins
    /// plans, since it counts only from the day they joined.
    public func trainingDays(from day: Int) -> Int {
        days.dropFirst(max(day, 0)).count { $0 != .rest }
    }

    /// The plan to save, for the member's week starting `weekStart`.
    public func plan(for member: MemberID, weekStart: LocalDay) throws(ContractsError) -> WeeklyPlan {
        try WeeklyPlan(member: member, weekStart: weekStart, days: days)
    }
}
