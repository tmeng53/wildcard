import Foundation

/// The rule for a name people type (a 其他 sport, a nickname), as the API's `nameText`: trimmed,
/// 1 to `maxLength` characters as people see them, on one line with plain spaces, showing
/// something, and never in a forced direction.
enum NameText {
    enum Fault: Error, Equatable {
        /// A line break, tab, other control character or unusual space.
        case notOneLine
        /// Empty, or longer than allowed; the trimmed length.
        case length(Int)
        /// Nothing visible in it, or a text-direction control.
        case invisible
    }

    /// The name trimmed, or why it isn't one.
    static func check(_ text: String, maxLength: Int) -> Result<String, Fault> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !trimmed.unicodeScalars.contains(where: {
                $0.properties.generalCategory == .control || $0.properties.isWhitespace && $0 != " " && $0 != "\u{3000}"
            })
        else { return .failure(.notOneLine) }
        guard (1...maxLength).contains(trimmed.count) else { return .failure(.length(trimmed.count)) }
        // A bidi control (U+202E flips what follows), or only format characters such as a lone
        // zero-width joiner, shows as a blank or garbled label. Joiners inside 🏃‍♀️ are fine.
        guard
            !trimmed.unicodeScalars.contains(where: { $0.properties.isBidiControl }),
            trimmed.unicodeScalars.contains(where: {
                $0.properties.generalCategory != .format && !$0.properties.isWhitespace
            })
        else { return .failure(.invisible) }
        return .success(trimmed)
    }
}
