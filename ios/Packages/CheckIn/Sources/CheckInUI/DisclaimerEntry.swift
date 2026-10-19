import Contracts

/// What the 请假条 bubble holds: the line being written, the member's own words, and whether
/// the writer refused to joke about them. The writer is asked about the member's words, so a
/// refusal holds on those words: while they post as the refused reason (spacing aside), nothing
/// can be posted and no suggested line is offered; once the member writes something else, it can.
struct DisclaimerEntry: Hashable, Sendable {
    private(set) var text = ""
    /// What the member typed themselves: the reason the writer riffs on, and what
    /// 用回我写的 brings back after a suggested line replaced it.
    private(set) var mine = ""
    /// The refused words as they would post, compared after `Disclaimer` trims them, so spaces
    /// around the same words don't unblock them.
    private var blocked: String?

    /// The member typed: the line, fitted to one line of at most `Disclaimer.maxLength`
    /// characters, becomes their own words.
    mutating func write(_ typed: String) {
        let fitted = Self.fit(typed)
        guard fitted != text else { return }
        text = fitted
        mine = fitted
    }

    /// The writer offered `line`: it replaces the line and keeps the member's own words.
    mutating func suggest(_ line: String) {
        text = Self.fit(line)
    }

    /// Whether a suggested line replaced words the member typed.
    var canRestore: Bool { !mine.isEmpty && text != mine }

    /// Puts the member's own words back.
    mutating func restore() {
        text = mine
    }

    /// The writer read the member's words as self-harm: they replace any suggested line, so the
    /// care line never sits next to a joke.
    mutating func block() {
        blocked = Self.posted(mine)
        text = mine
    }

    /// Whether the member's words are the refused ones.
    var isBlocked: Bool {
        blocked != nil && Self.posted(mine) == blocked
    }

    /// The line to post, or nil while it is empty, too long or blocked.
    var disclaimer: Disclaimer? {
        isBlocked ? nil : try? Disclaimer(text)
    }

    private static func posted(_ text: String) -> String? {
        (try? Disclaimer(text))?.text
    }

    /// The next lines to offer: the writer's `lines` first, then `spare` ones, each fitted, each
    /// once, none of them `shown`, at most `count` of them. So a refill never repeats a line.
    static func newLines(from lines: [String], spare: [String], shown: Set<String>, count: Int = 3) -> [String] {
        var taken = shown
        return (lines + spare).map(fit).filter { !$0.isEmpty && taken.insert($0).inserted }.prefix(count).map { $0 }
    }

    static func fit(_ text: String) -> String {
        String(text.filter { !$0.isNewline }.prefix(Disclaimer.maxLength))
    }
}
