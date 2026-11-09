/// 「执教 N 天」 under a week, then 「执教 N 周」 in whole weeks (Tracy, 2026-11-09), so a coach
/// hired on a Sunday isn't in its second week on Monday.
public enum CoachTenure: Equatable, Sendable {
    case days(Int)
    case weeks(Int)

    /// From the days coached, the hire day counting 1.
    public init(days: Int) {
        self = days < 7 ? .days(max(days, 1)) : .weeks(days / 7)
    }
}
