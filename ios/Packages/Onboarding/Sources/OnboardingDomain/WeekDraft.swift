import Contracts

/// The member's typical week, drawn on the week's poster: what each day is, a sport picked in
/// the step before, a training day with no sport named, or 休息. Every week follows it until
/// it is changed for itself. Tapping a day selects it, and picking what it is moves on to the
/// next day, so a whole week takes a few taps. Days of this week that are already over can't
/// change here; the poster leaves them blank, and the week doesn't count them.
public struct WeekDraft: Hashable, Sendable {
    public private(set) var days: [PlanDay]
    /// The day the choices below the poster are for, from 0 (the week's first day).
    public private(set) var selected: Int
    /// How many of the week's days are over: 0 on its first day, 6 on its last.
    public let daysGone: Int
    /// What a day can be: each sport picked, or one training day with no sport if none was
    /// picked, then 休息.
    public let choices: [PlanDay]

    /// The training days for each number of them, spread out over the week; five rest on
    /// Wednesday and Sunday, as the approved design shows.
    static let trainingDays: [[Int]] = [[2], [1, 3], [0, 2, 4], [0, 1, 3, 4], [0, 1, 3, 4, 5]]

    /// One training day for each sport picked, at most five, in the order picked; a training
    /// day with no sport named if none was. `daysGone`: how far into the week sign-up happens,
    /// clamped to `0...6`.
    public init(sports: [Activity], daysGone: Int) {
        let gone = min(max(daysGone, 0), WeeklyPlan.dayCount - 1)
        let trainings: [PlanDay] = sports.isEmpty ? [.train(nil)] : sports.map { .train($0) }
        let planned = Self.trainingDays[min(trainings.count, Self.trainingDays.count) - 1]
        days = (0..<WeeklyPlan.dayCount).map { index in
            planned.firstIndex(of: index).map { trainings[$0] } ?? .rest
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
