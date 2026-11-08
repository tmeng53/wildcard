import Foundation

/// A squad's time zone (小队时区) as its members see it: the clock its Sunday 8pm 战报 and the
/// coach's daily wake keep, which its captain sets. Each member's own day keeps their own zone.
public struct SquadTimeZone: Hashable, Sendable {
    /// Every squad's clock before it had one of its own.
    public static let newYork = "America/New_York"

    /// This week's zone (an IANA name such as `Asia/Taipei`).
    public var timeZone: String
    /// Next week's: a captain's change counts from the next week.
    public var nextTimeZone: String
    /// The viewer is the captain, the only one who sets it.
    public let canChange: Bool

    public init(timeZone: String, nextTimeZone: String, canChange: Bool) {
        self.timeZone = timeZone
        self.nextTimeZone = nextTimeZone
        self.canChange = canChange
    }
}
