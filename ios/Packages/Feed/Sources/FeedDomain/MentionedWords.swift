import Contracts

/// Words split into plain runs and the 「@名字」 of the people they @, so a comment or a coach's
/// line shows each @ as a tag and a tap on a teammate's opens their card. The @s are known by
/// id: two teammates of the same name each get their own 「@名字」, in the order written.
public struct MentionedWords: Hashable, Sendable {
    /// Whom a tag stands for.
    public enum Person: Hashable, Sendable {
        case member(MemberID)
        case coach(CoachID)
        /// Someone the app can't name now, such as a teammate who has left the squad: their
        /// 「@名字」 shows as written, greyed, and opens nothing.
        case unnamed(MemberID)
    }

    public enum Run: Hashable, Sendable {
        case plain(String)
        /// 「@名字」, the `@` and the name as written.
        case tag(String, Person)
    }

    public let runs: [Run]

    /// - Parameters:
    ///   - people: whom `text` @s, in the order written, each with the name its 「@」 carries.
    ///     One whose 「@名字」 isn't in the words stays plain, so nothing is made up.
    ///   - unnamed: whom `text` @s without a name the app knows, in the order written. Each takes
    ///     the next 「@」 left over, up to the space the box and the coach put after a name; one
    ///     longer than a nickname may be stays plain.
    public init(_ text: String, people: [(person: Person, name: String)], unnamed: [MemberID] = []) {
        var claimed: [Range<String.Index>: Person] = [:]
        // Longest name first, so 「@毛头头」 isn't taken as 「@毛头」 and the rest; the same name
        // keeps its order, so the first of two teammates called Mia gets the first 「@Mia」.
        let longestFirst = people.enumerated()
            .filter { !$0.element.name.isEmpty }
            .sorted { ($0.element.name.count, -$0.offset) > ($1.element.name.count, -$1.offset) }
        for (_, (person, name)) in longestFirst {
            var from = text.startIndex
            while let found = text.range(of: "@\(name)", range: from..<text.endIndex) {
                if Self.endsName(found, in: text), !claimed.keys.contains(where: { $0.overlaps(found) }) {
                    claimed[found] = person
                    break
                }
                from = found.upperBound
            }
        }
        var from = text.startIndex
        for member in unnamed {
            guard let found = Self.nextUnclaimedAt(in: text, from: &from, claimed: claimed.keys) else { break }
            claimed[found] = .unnamed(member)
        }
        var runs: [Run] = []
        var cursor = text.startIndex
        for range in claimed.keys.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if cursor < range.lowerBound { runs.append(.plain(String(text[cursor..<range.lowerBound]))) }
            if let person = claimed[range] { runs.append(.tag(String(text[range]), person)) }
            cursor = range.upperBound
        }
        if cursor < text.endIndex { runs.append(.plain(String(text[cursor...]))) }
        self.runs = runs
    }

    /// Whether `found` is a whole 「@名字」, not the start of a longer one (「@Mia」 in 「@Miao」): it
    /// ends the text or is followed by a space or punctuation, as the box and the coach write it.
    private static func endsName(_ found: Range<String.Index>, in text: String) -> Bool {
        guard found.upperBound < text.endIndex else { return true }
        let next = text[found.upperBound]
        return !(next.isLetter || next.isNumber)
    }

    /// The next 「@名字」 from `from` that no tag has taken: the `@` and what follows it up to a
    /// space or the end, when that is as long as a nickname may be.
    private static func nextUnclaimedAt(
        in text: String, from: inout String.Index, claimed: some Collection<Range<String.Index>>
    ) -> Range<String.Index>? {
        while let sign = text[from...].firstIndex(of: "@") {
            let end = text[sign...].firstIndex(where: \.isWhitespace) ?? text.endIndex
            let found = sign..<end
            from = end
            let length = text.distance(from: sign, to: end) - 1
            if (1...Nickname.maxLength).contains(length), !claimed.contains(where: { $0.overlaps(found) }) {
                return found
            }
        }
        return nil
    }
}
