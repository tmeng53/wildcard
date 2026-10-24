/// Why the feed didn't load, or a reaction didn't go through. Each case is something the caller
/// can act on; the app turns them into friendly copy, never a warning.
public enum FeedError: Error, Equatable, Sendable {
    /// Nobody reacts to their own post.
    case ownPost
    /// The server couldn't be reached; trying again is safe.
    case notSent
    /// The member isn't signed in any more.
    case signedOut
    /// The member isn't in the squad any more.
    case notInSquad
    /// The post is gone: its author deleted it or left the squad.
    case postGone
    /// The server said no for a reason this build doesn't know. Trying again won't help.
    case refused
}
