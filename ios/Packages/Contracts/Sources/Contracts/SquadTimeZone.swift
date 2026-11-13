import Foundation

/// A squad's time zone (小队时区) as its members see it: the clock its Sunday 8pm 战报 and the
/// coach's daily wake keep, which its captain sets. Each member's own day keeps their own zone.
public struct SquadTimeZone: Hashable, Sendable {
    /// Every squad's clock before it had one of its own.
    public static let newYork = "America/New_York"
    /// `newYork` as a clock.
    public static let newYorkClock = TimeZone(identifier: newYork) ?? .gmt

    /// This week's zone (an IANA name such as `Asia/Taipei`).
    public var timeZone: String
    /// Next week's, the captain's latest pick, which 比赛时区 shows: the same as `timeZone` unless
    /// the change came once this week's Sunday 8pm had passed on the old clock or the new one, when
    /// it counts from next week.
    public var nextTimeZone: String
    /// The viewer is the captain, the only one who sets it.
    public let canChange: Bool

    /// `nextTimeZone` left out is `timeZone`: no change waits.
    public init(timeZone: String, nextTimeZone: String? = nil, canChange: Bool) {
        self.timeZone = timeZone
        self.nextTimeZone = nextTimeZone ?? timeZone
        self.canChange = canChange
    }
}
