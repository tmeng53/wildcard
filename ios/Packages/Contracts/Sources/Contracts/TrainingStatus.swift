/// Where a member's day stands for training. There is no "missed" state: a day
/// without a check-in is simply not checked in.
public enum TrainingStatus: Hashable, Sendable {
    /// At least one 练了. Wins over a 请假条 posted earlier the same day.
    case trained
    /// A 今日请假条 and no 练了.
    case disclaimer
    case notCheckedIn

    /// Whether a 今日请假条 may still be posted today: not after a 练了, and one a day.
    public var allowsDisclaimer: Bool { self == .notCheckedIn }
}
