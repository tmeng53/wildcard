import Foundation

/// A squad's weekly goal (小队每周目标) as its members see it: how many days each member trains
/// on average (人均 N 天), which its captain sets, and how the squad did lately. The squad's goal
/// for a week is that times its members.
public struct SquadWeeklyGoal: Hashable, Sendable {
    /// How the squad trained over its latest finished weeks.
    public struct Recent: Hashable, Sendable {
        /// How many finished weeks it averages, 1 to 4.
        public let weeks: Int
        /// The days each member trained on average in them, to one decimal.
        public let daysPerMember: Double

        public init(weeks: Int, daysPerMember: Double) {
            self.weeks = weeks
            self.daysPerMember = daysPerMember
        }
    }

    /// The goals a captain picks from.
    public static let choices = 1...7

    /// This week's goal.
    public var daysPerMember: Int
    /// Next week's: a captain's change counts from the next week.
    public var nextDaysPerMember: Int
    /// The viewer is the captain, the only one who sets it.
    public let canChange: Bool
    /// Nil until the squad has a finished week.
    public let recent: Recent?

    public init(daysPerMember: Int, nextDaysPerMember: Int, canChange: Bool, recent: Recent?) {
        self.daysPerMember = daysPerMember
        self.nextDaysPerMember = nextDaysPerMember
        self.canChange = canChange
        self.recent = recent
    }
}
