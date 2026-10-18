import Contracts

/// Why a check-in rule said no. Each case is something the caller can act on; the
/// app turns them into friendly copy, never a warning.
public enum CheckInError: Error, Equatable, Sendable {
    /// Only today's check-ins (counting the early-morning grace) can be posted or deleted.
    case notToday(LocalDay)
    /// The check-in names a squad the member isn't in.
    case notInSquad(SquadID)
    /// A 免责声明 on a day that already has a 练了. The two are opposites; the day is trained.
    case alreadyTrained
    /// The check-in or plan belongs to someone else.
    case otherMember(MemberID)
    /// No check-in with this id in the member's log.
    case notFound(CheckInID)
    /// Date arithmetic left the years `LocalDay` supports.
    case dayOutOfRange
}
