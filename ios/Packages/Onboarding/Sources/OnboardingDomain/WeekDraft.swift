import Contracts

/// 定个本周目标, drawn on the week's poster: what each day of this week is, a sport picked in
/// the step before, a training day with no sport named, or 休息. Tapping a day selects it, and
/// picking what it is moves on to the next day, so a whole week takes a few taps. Days of this
/// week that are already over can't change, as on any weekly plan; the poster leaves them blank rather
/// than calling them 休息, though the plan saves them as rest.
public struct WeekDraft: Hashable, Sendable {
    public private(set) var days: [PlanDay]
    /// The day the choices below the poster are for, from 0 (the week's first day).
    public private(set) var selected: Int
    /// How many of the week's days are over: 0 on its first day, 6 on its last.
    public let daysGone: Int
    /// What a day can be: each sport picked, or one training day with no sport if none was
    /// picked, then 休息.
    public let choices: [PlanDay]

    /// Training days start on every day but the third and the seventh, taking the picked
    /// sports in turn: five days, two of rest, as the approved design shows.
    static let restDays: Set<Int> = [2, 6]

    /// `daysGone`: how far into the week sign-up happens, clamped to `0...6`.
    public init(sports: [Activity], daysGone: Int) {
        let gone = min(max(daysGone, 0), WeeklyPlan.dayCount - 1)
        let trainings: [PlanDay] = sports.isEmpty ? [.train(nil)] : sports.map { .train($0) }
        var next = 0
        days = (0..<WeeklyPlan.dayCount).map { index in
            guard index >= gone, !Self.restDays.contains(index) else { return .rest }
            defer { next += 1 }
            return trainings[next % trainings.count]
        }
        self.daysGone = gone
        selected = gone
        choices = trainings + [.rest]
    }

    /// Whether a day can still change: today and the days after it.
    public func isOpen(_ index: Int) -> Bool {
        (daysGone..<WeeklyPlan.dayCount).contains(index)
    }

    public mutating func select(_ index: Int) {
        guard isOpen(index) else { return }
        selected = index
    }

    /// Sets the selected day, then selects the next open day, back to today after the last.
    /// True when a rest day became a training day, which the character hops for.
    @discardableResult
    public mutating func set(_ day: PlanDay) -> Bool {
        let becameTraining = days[selected] == .rest && day != .rest
        days[selected] = day
        selected = selected + 1 < WeeklyPlan.dayCount ? selected + 1 : daysGone
        return becameTraining
    }

    /// 每周训练 N/7 天: the week's training days.
    public var trainingDays: Int {
        days.count { $0 != .rest }
    }

    /// The plan to save, for the member's week starting `weekStart`.
    public func plan(for member: MemberID, weekStart: LocalDay) throws(ContractsError) -> WeeklyPlan {
        try WeeklyPlan(member: member, weekStart: weekStart, days: days)
    }
}
