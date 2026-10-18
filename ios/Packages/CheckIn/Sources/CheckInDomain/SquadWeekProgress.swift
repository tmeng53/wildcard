/// 本周小队 x/y: how far the squad has come this week against everyone's own plan. The goal
/// is the sum of every member's planned training days; done is the days each member trained,
/// several workouts on one day counting once. 免责 days never count, days beyond someone's
/// plan do, and the bar stops at full. Nobody's share is shown.
public struct SquadWeekProgress: Hashable, Sendable {
    public let done: Int
    public let goal: Int

    public init(done: Int, goal: Int) {
        self.done = max(done, 0)
        self.goal = max(goal, 0)
    }

    /// From each member's week. A member with no plan adds trained days but no goal.
    public init(members: [WeekSummary]) {
        self.init(
            done: members.reduce(0) { $0 + $1.trainedDays },
            goal: members.reduce(0) { $0 + ($1.plannedTrainingDays ?? 0) })
    }

    /// How full the bar is, from 0 to 1. Empty while nobody has a plan.
    public var fraction: Double {
        guard goal > 0 else { return 0 }
        return min(Double(done) / Double(goal), 1)
    }

    /// The same week after one more member-day of training.
    public func addingTrainedDay() -> SquadWeekProgress {
        SquadWeekProgress(done: done + 1, goal: goal)
    }
}

extension TrainingStatus {
    /// Whether a 今日免责声明 may still be posted today: not after a 练了, and one a day.
    public var allowsDisclaimer: Bool { self == .notCheckedIn }
}
