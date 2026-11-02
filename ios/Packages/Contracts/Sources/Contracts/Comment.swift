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

/// A comment under a check-in, from its author or a teammate who can see it: one level deep,
/// never edited; its writer may delete it.
public struct Comment: Hashable, Sendable, Identifiable {
    public let id: CommentID
    public let member: MemberID
    public let text: CommentText
    /// Whom it replies to (回复 Mia：…), when it does.
    public let replyTo: MemberID?
    public let commentedAt: Timestamp

    public init(id: CommentID, member: MemberID, text: CommentText, replyTo: MemberID?, commentedAt: Timestamp) {
        self.id = id
        self.member = member
        self.text = text
        self.replyTo = replyTo
        self.commentedAt = commentedAt
    }
}
