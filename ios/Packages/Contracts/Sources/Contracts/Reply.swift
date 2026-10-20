/// A teammate's reply on someone's 今日请假条, one per member, apart from their reaction: a
/// teammate can say 准了 and still laugh at it.
public struct Reply: Hashable, Sendable {
    public let member: MemberID
    public let kind: ReplyKind
    public let repliedAt: Timestamp

    public init(member: MemberID, kind: ReplyKind, repliedAt: Timestamp) {
        self.member = member
        self.kind = kind
        self.repliedAt = repliedAt
    }
}

/// Which reply: 准了, 抱抱 or 明天一起. The app shows each with its own copy.
public enum ReplyKind: String, CaseIterable, Hashable, Sendable {
    case approved, hug, together
}
