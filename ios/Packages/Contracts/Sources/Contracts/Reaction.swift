/// A teammate's reaction on a check-in: one emoji per member, which they can change.
public struct Reaction: Hashable, Sendable {
    public let member: MemberID
    public let emoji: Emoji
    public let reactedAt: Timestamp

    public init(member: MemberID, emoji: Emoji, reactedAt: Timestamp) {
        self.member = member
        self.emoji = emoji
        self.reactedAt = reactedAt
    }
}
