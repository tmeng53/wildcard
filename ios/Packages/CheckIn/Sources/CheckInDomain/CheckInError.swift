/// Why a check-in, or loading the squad's today, didn't work. Each case is something the caller
/// can act on; the app turns them into friendly copy, never a warning.
public enum CheckInError: Error, Equatable, Sendable {
    /// A 请假条 on a day that already has a 练了. The two are opposites; the day is trained.
    case alreadyTrained
    /// A second 请假条 on the same day. One a day is enough; there is no weekly limit.
    case disclaimerAlreadyPosted
    /// The server couldn't be reached, so nothing was saved; trying again is safe.
    case notSent
    /// A picked photo couldn't be read as an image.
    case unreadablePhoto
    /// The photo was refused for its type or size.
    case photoRejected
    /// The member isn't signed in any more; nothing is lost, it goes out after they sign in.
    case signedOut
    /// The member isn't in the squad any more.
    case notInSquad
    /// It waited too long to go out (the server takes check-ins up to 48 hours late), or the
    /// phone's clock is off.
    case outOfTime
    /// The server said no for a reason this build doesn't know. Trying again won't help.
    case refused
}
