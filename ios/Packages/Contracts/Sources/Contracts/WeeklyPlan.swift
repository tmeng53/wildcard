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
