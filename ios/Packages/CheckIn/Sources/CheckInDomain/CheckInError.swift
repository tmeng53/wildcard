/// Why a check-in rule said no. Each case is something the caller can act on; the
/// app turns them into friendly copy, never a warning.
public enum CheckInError: Error, Equatable, Sendable {
    /// A 请假条 on a day that already has a 练了. The two are opposites; the day is trained.
    case alreadyTrained
    /// A second 请假条 on the same day. One a day is enough; there is no weekly limit.
    case disclaimerAlreadyPosted
    /// The check-in didn't reach the server, so nothing was saved; trying again is safe.
    case notSent
    /// A picked photo couldn't be read as an image.
    case unreadablePhoto
}
