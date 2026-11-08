/// What a member writes us on 意见反馈: trimmed, 1 to `maxLength` characters, and it may span
/// lines.
public struct FeedbackText: Hashable, Sendable {
    /// Characters, counted as people see them. The API's limit; `APIContract`'s tests fail when
    /// the two differ.
    public static let maxLength = 1000
    /// The most screenshots a message carries; the API's limit too.
    public static let maxScreenshots = 3

    public let text: String

    public init(_ text: String) throws(ContractsError) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...Self.maxLength).contains(trimmed.count) else { throw .feedbackLength(trimmed.count) }
        self.text = trimmed
    }
}
