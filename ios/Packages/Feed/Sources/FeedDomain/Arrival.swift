import Contracts

/// A teammate's reaction on one of the member's own posts.
public struct Arrival: Hashable, Sendable {
    public let post: CheckInID
    public let member: MemberID
    public let emoji: Emoji
    public let moment: Timestamp
}
