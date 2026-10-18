import Contracts

/// Where a member's day stands for training. There is no "missed" state: a day
/// without a check-in is simply not checked in.
public enum TrainingStatus: Hashable, Sendable {
    /// At least one 练了. Wins over a 免责声明 posted earlier the same day.
    case trained
    /// A 今日免责声明 and no 练了.
    case disclaimer
    case notCheckedIn
}

/// One member's check-ins and the rules that read them. Every count is worked out
/// from the check-ins themselves, so deleting one updates everything and nothing
/// ever resets.
public struct CheckInLog: Hashable, Sendable {
    public let member: MemberID
    /// Only this member's check-ins, in the order given.
    public let checkIns: [CheckIn]

    /// Keeps only `member`'s check-ins from `checkIns`.
    public init(member: MemberID, checkIns: some Sequence<CheckIn>) {
        self.member = member
        self.checkIns = checkIns.filter { $0.member == member }
    }

    /// The log as `squad` sees it: only check-ins sent to that squad. A squad left out
    /// of a check-in sees the member as not checked in.
    public func seen(by squad: SquadID) -> CheckInLog {
        CheckInLog(member: member, checkIns: checkIns.filter { $0.audience.squads.contains(squad) })
    }

    public func training(on day: LocalDay) -> TrainingStatus {
        let entries = checkIns.filter { $0.day == day }.map(\.entry)
        if entries.contains(where: \.isTraining) { return .trained }
        if entries.contains(where: \.isDisclaimer) { return .disclaimer }
        return .notCheckedIn
    }

    /// At least one 健康餐 that day. 放纵餐忏悔 never counts.
    public func hadHealthyMeal(on day: LocalDay) -> Bool {
        checkIns.contains { $0.day == day && $0.entry.isHealthyMeal }
    }

    /// Every day ever with a 练了. Several 练了 on one day count once.
    public var lifetimeTrainedDays: Int {
        Set(checkIns.filter(\.entry.isTraining).map(\.day)).count
    }

    /// The week with no plan to compare against.
    public func summary(of week: Week) -> WeekSummary {
        WeekSummary(week: week, plan: nil, log: self)
    }

    /// The week the plan covers, with 本周 x/y against its training days.
    public func summary(for plan: WeeklyPlan) throws(CheckInError) -> WeekSummary {
        guard plan.member == member else { throw .otherMember(plan.member) }
        return WeekSummary(week: try Week(startingOn: plan.weekStart), plan: plan, log: self)
    }

    /// Checks that `checkIn` may be posted now. Any number of 练了 and meals a day is
    /// fine; a 免责声明 is at most one a day, and never after a 练了 the same day.
    public func checkPost(_ checkIn: CheckIn, today: LocalDay, memberSquads: Set<SquadID>) throws(CheckInError) {
        guard checkIn.member == member else { throw .otherMember(checkIn.member) }
        guard checkIn.day == today else { throw .notToday(checkIn.day) }
        if let squad = checkIn.audience.squads.first(where: { !memberSquads.contains($0) }) {
            throw .notInSquad(squad)
        }
        if checkIn.entry.isDisclaimer {
            switch training(on: today) {
            case .trained: throw .alreadyTrained
            case .disclaimer: throw .disclaimerAlreadyPosted
            case .notCheckedIn: break
            }
        }
    }

    /// Checks that `requester` may delete the check-in: their own, and only on the day
    /// it counts for.
    public func checkDelete(_ id: CheckInID, by requester: MemberID, today: LocalDay) throws(CheckInError) {
        guard requester == member else { throw .otherMember(requester) }
        guard let checkIn = checkIns.first(where: { $0.id == id }) else { throw .notFound(id) }
        guard checkIn.day == today else { throw .notToday(checkIn.day) }
    }
}

/// A member's week: 本周练了几天 against the plan, and 本周健康餐几天.
public struct WeekSummary: Hashable, Sendable {
    public struct Day: Hashable, Sendable {
        public let day: LocalDay
        /// What the plan says for the day, when there is a plan.
        public let plan: PlanDay?
        public let training: TrainingStatus
        public let hadHealthyMeal: Bool
    }

    public let week: Week
    /// Seven days, the week's first day first.
    public let days: [Day]
    /// Days with a 练了, planned or not. Can go above `plannedTrainingDays`.
    public let trainedDays: Int
    /// Training days in the plan; `nil` without a plan.
    public let plannedTrainingDays: Int?
    /// Days with at least one 健康餐.
    public let healthyMealDays: Int

    init(week: Week, plan: WeeklyPlan?, log: CheckInLog) {
        let days = week.days.enumerated().map { index, day in
            Day(
                day: day, plan: plan?.days[index], training: log.training(on: day),
                hadHealthyMeal: log.hadHealthyMeal(on: day))
        }
        self.week = week
        self.days = days
        trainedDays = days.count(where: { $0.training == .trained })
        plannedTrainingDays = plan.map { $0.days.count(where: { $0 != .rest }) }
        healthyMealDays = days.count(where: \.hadHealthyMeal)
    }
}

extension CheckIn.Entry {
    var isTraining: Bool {
        if case .trained = self { true } else { false }
    }

    var isDisclaimer: Bool {
        if case .disclaimer = self { true } else { false }
    }

    var isHealthyMeal: Bool {
        if case .healthyMeal = self { true } else { false }
    }
}
