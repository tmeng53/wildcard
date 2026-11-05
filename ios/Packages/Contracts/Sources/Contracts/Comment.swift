/// What a comment under a 动态 post says: trimmed, 1 to `maxLength` characters, and it may span
/// lines.
public struct CommentText: Hashable, Sendable {
    /// Characters, counted as people see them. The API's limit; `APIContract`'s tests fail when
    /// the two differ.
    public static let maxLength = 100

    public let text: String

    public init(_ text: String) throws(ContractsError) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...Self.maxLength).contains(trimmed.count) else { throw .commentLength(trimmed.count) }
        self.text = trimmed
    }
}

/// Whom a comment replies to: a member who can see the post (回复 Mia：…), or the squad's coach
/// that said something under it (回复 毛头：…), which answers it.
public enum ReplyTarget: Hashable, Sendable {
    case member(MemberID)
    case coach(CoachID)
}

/// Whom a comment @s: up to `maxMembers` people who can see the post, each told by push, and the
/// squad's coach, which answers it.
public struct Mentions: Hashable, Sendable {
    /// The API's limit; `APIContract`'s tests fail when the two differ.
    public static let maxMembers = 8
    public static let none = Mentions(members: [], coach: nil)

    /// In the order written, each once.
    public let members: [MemberID]
    public let coach: CoachID?

    public init(members: [MemberID], coach: CoachID?) {
        var seen = Set<MemberID>()
        self.members = Array(members.filter { seen.insert($0).inserted }.prefix(Self.maxMembers))
        self.coach = coach
    }

    public var isEmpty: Bool { members.isEmpty && coach == nil }
}

/// A comment under a check-in, from its author or a teammate who can see it: one level deep,
/// never edited; its writer may delete it.
public struct Comment: Hashable, Sendable, Identifiable {
    public let id: CommentID
    public let member: MemberID
    public let text: CommentText
    /// Whom it replies to, when it does.
    public let replyTo: ReplyTarget?
    /// Whom it @s.
    public let mentions: Mentions
    public let commentedAt: Timestamp

    public init(
        id: CommentID, member: MemberID, text: CommentText, replyTo: ReplyTarget?, mentions: Mentions = .none,
        commentedAt: Timestamp
    ) {
        self.id = id
        self.member = member
        self.text = text
        self.replyTo = replyTo
        self.mentions = mentions
        self.commentedAt = commentedAt
    }

    /// The member it replies to, when it replies to one.
    public var replyToMember: MemberID? {
        if case .member(let member) = replyTo { member } else { nil }
    }
}
