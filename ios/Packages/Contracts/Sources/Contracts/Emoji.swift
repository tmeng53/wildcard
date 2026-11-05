/// One emoji, as people see it: a single character that draws as an emoji, skin tones, flags and
/// joined families included. A teammate's reaction is one of these.
public struct Emoji: Hashable, Sendable, CustomStringConvertible {
    /// ❤️, which a double tap on a photo leaves.
    public static let heart = Emoji(unchecked: "❤️")

    public let text: String

    public init(_ text: String) throws(ContractsError) {
        guard text.count == 1, let first = text.unicodeScalars.first, Self.drawsAsEmoji(text, first: first) else {
            throw .notAnEmoji(text)
        }
        self.text = text
    }

    private init(unchecked text: String) { self.text = text }

    public var description: String { text }

    /// A digit or `#` is "emoji" to Unicode too, so a plain one doesn't count: it has to draw as
    /// an emoji by default, ask for it (U+FE0F), or be a sequence (keycap, flag, ZWJ, skin tone).
    private static func drawsAsEmoji(_ text: String, first: Unicode.Scalar) -> Bool {
        guard first.properties.isEmoji else { return false }
        return first.properties.isEmojiPresentation || text.unicodeScalars.count > 1
    }
}
