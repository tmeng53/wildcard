/// 口头禅: what the member's character shouts when the squad cheers a teammate's 练了. One line
/// of at most `maxLength` characters, emoji welcome. The API also refuses links, which only it
/// checks, so the rule lives in one place.
public struct Catchphrase: Hashable, Sendable {
    /// Characters, counted as people see them (a Chinese character or emoji is one). The API's
    /// limit; `APIContract`'s tests fail when the two differ.
    public static let maxLength = 10

    public let text: String

    public init(_ text: String) throws(ContractsError) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(where: \.isNewline) else { throw .multilineCatchphrase }
        guard (1...Self.maxLength).contains(trimmed.count) else { throw .catchphraseLength(trimmed.count) }
        self.text = trimmed
    }
}
