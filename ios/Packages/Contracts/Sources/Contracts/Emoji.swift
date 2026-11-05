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

extension Emoji {
    /// The emoji bar's six, in the approved order, wherever a member reacts (动态, the 6pm push,
    /// the squad chat); ＋ offers any other.
    public static let quick: [Emoji] = ["❤️", "💪", "😂", "🤤", "😮", "😡"].compactMap { try? Emoji($0) }

    /// Every single emoji ＋ offers wherever a member reacts, faces first, each skin tone left to
    /// the keyboard.
    public static let all: [Emoji] = {
        let ranges: [ClosedRange<UInt32>] = [
            0x1F600...0x1F64F, 0x1F900...0x1F9FF, 0x1FA70...0x1FAFF, 0x1F300...0x1F5FF, 0x1F680...0x1F6FF,
            0x2600...0x27BF,
        ]
        var emoji: [Emoji] = []
        for range in ranges {
            for value in range {
                guard let scalar = Unicode.Scalar(value), scalar.properties.isEmojiPresentation,
                    !(0x1F3FB...0x1F3FF).contains(value), let one = try? Emoji(String(scalar))
                else { continue }
                emoji.append(one)
            }
        }
        // ❤️ draws as an emoji only with its variation selector.
        if let heart = try? Emoji("❤️") { emoji.insert(heart, at: 0) }
        return emoji
    }()
}
