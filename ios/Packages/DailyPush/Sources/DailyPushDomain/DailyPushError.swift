/// Why the push's view can't show, or a reaction didn't go through. Each case is something the
/// caller can act on; the view never shows a warning.
public enum DailyPushError: Error, Equatable, Sendable {
    /// The push carried no squad day this build can read: an older server, or another push.
    case unreadable
    /// Nobody reacts to their own post.
    case ownPost
    /// The post isn't in the push.
    case unknownPost
    /// The reaction didn't reach the server; the row goes back to what it was.
    case notSent
}
