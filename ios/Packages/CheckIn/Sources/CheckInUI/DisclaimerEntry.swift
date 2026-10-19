import Contracts

/// What the 免责声明 card holds: the line being written, and whether the writer refused to joke
/// about it. A refused reason can't be posted, so teammates never see it; any edit, a dice roll
/// or a picked draft makes a new line that can.
struct DisclaimerEntry: Hashable, Sendable {
    private(set) var text = ""
    private(set) var isBlocked = false

    /// Sets the line, fitted to one line of at most `Disclaimer.maxLength` characters.
    mutating func write(_ typed: String) {
        let fitted = Self.fit(typed)
        guard fitted != text else { return }
        text = fitted
        isBlocked = false
    }

    /// The writer read the current line as self-harm.
    mutating func block() {
        isBlocked = true
    }

    /// The line to post, or nil while it is empty, too long or blocked.
    var disclaimer: Disclaimer? {
        isBlocked ? nil : try? Disclaimer(text)
    }

    static func fit(_ text: String) -> String {
        String(text.filter { !$0.isNewline }.prefix(Disclaimer.maxLength))
    }
}
