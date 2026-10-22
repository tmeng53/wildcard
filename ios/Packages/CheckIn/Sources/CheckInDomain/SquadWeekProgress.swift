/// 本周小队 x/y: how far the squad has come this week against everyone's own plan. The goal
/// is the sum of every member's planned training days; done is the days each member trained,
/// several workouts on one day counting once. 请假 days never count, days beyond someone's
/// plan do, and the bar stops at full. Nobody's share is shown.
public struct SquadWeekProgress: Hashable, Sendable {
    public let done: Int
    public let goal: Int

    public init(done: Int, goal: Int) {
        self.done = max(done, 0)
        self.goal = max(goal, 0)
    }

    /// How full the bar is, from 0 to 1. Empty while nobody has a plan.
    public var fraction: Double {
        guard goal > 0 else { return 0 }
        return min(Double(done) / Double(goal), 1)
    }
}
