/// A member's plan for one week: which days they train and which are rest days.
/// Planned training days are what 本周 counts against. The rules
/// (locking days once they start, carrying last week's plan over) live in the
/// `CheckIn` package, not here. Its wire shape is written in the API's Zod schemas when the
/// plan's routes land, and generated into `APIContract` like the check-in's.
public struct WeeklyPlan: Hashable, Sendable {
    /// How many days a plan has: one week.
    public static let dayCount = 7

    public let member: MemberID
    /// The plan's first day. Its weekday is the member's chosen week start.
    public let weekStart: LocalDay
    /// Exactly seven days, `weekStart` first.
    public let days: [PlanDay]

    public init(member: MemberID, weekStart: LocalDay, days: [PlanDay]) throws(ContractsError) {
        guard days.count == Self.dayCount else { throw .planLength(days.count) }
        self.member = member
        self.weekStart = weekStart
        self.days = days
    }
}

/// One planned day: train (optionally naming the sport) or 休息.
public enum PlanDay: Hashable, Sendable {
    case train(Activity?)
    case rest
}

extension PlanDay {
    /// The day a week's character acts out: the training planned most, the one planned first on
    /// a tie (a training day with no sport named counts as one kind), or 休息 when every day rests.
    public static func mostPlanned(in days: [PlanDay]) -> PlanDay {
        let trainings = days.filter { $0 != .rest }
        let counts = Dictionary(trainings.map { ($0, 1) }, uniquingKeysWith: +)
        // `max(by:)` keeps the first of equals: the one planned earliest.
        return trainings.max { counts[$0, default: 0] < counts[$1, default: 0] } ?? .rest
    }
}
