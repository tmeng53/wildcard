/// A teammate's reaction on a check-in, one per member, like a kudos.
public struct Reaction: Hashable, Sendable {
    public let member: MemberID
    public let kind: ReactionKind
    public let reactedAt: Timestamp

    public init(member: MemberID, kind: ReactionKind, reactedAt: Timestamp) {
        self.member = member
        self.kind = kind
        self.reactedAt = reactedAt
    }
}

/// Which reaction: 加油, 名场面 or 笑死. The app shows each with its own copy.
public enum ReactionKind: String, CaseIterable, Hashable, Sendable {
    case cheer, highlight, lol
}
