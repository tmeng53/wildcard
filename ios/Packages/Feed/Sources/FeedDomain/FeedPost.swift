import Contracts

/// One check-in in the feed, with teammates' emoji.
public struct FeedPost: Hashable, Sendable, Identifiable {
    public let checkIn: CheckIn
    public internal(set) var reactions: Responses<Emoji>

    public init(checkIn: CheckIn, reactions: Responses<Emoji> = .init()) {
        self.checkIn = checkIn
        self.reactions = reactions
    }

    public var id: CheckInID { checkIn.id }
    public var author: MemberID { checkIn.member }

    /// Teammates react; nobody reacts to their own post.
    public func canRespond(_ viewer: MemberID) -> Bool { viewer != author }
}

/// A move from the character's move library, by id, which the author's character plays when a
/// teammate reacts. A player that doesn't know an id plays the persona's cheer.
public struct MoveID: Hashable, Sendable, CustomStringConvertible {
    /// The persona's own cheer: any emoji without a move of its own.
    public static let cheer = MoveID("cheer")

    /// The emoji that have a move of their own; the rest cheer. 第一期's approved table;
    /// 第二期's coach picks moves and falls back to it.
    static let byEmoji: [String: MoveID] = [
        "❤️": MoveID("heart"),
        "💪": MoveID("flex"),
        "😎": MoveID("chin-up"), "🏆": MoveID("chin-up"), "👑": MoveID("chin-up"),
        "😂": MoveID("laugh-bend"),
        "🤤": MoveID("drool"),
        "😮": MoveID("shocked"),
        "😡": MoveID("pout"),
    ]

    public let id: String

    public init(_ id: String) { self.id = id }

    /// The move an emoji makes the author's character play, whatever its skin tone.
    public init(_ emoji: Emoji) {
        var plain = String.UnicodeScalarView()
        plain.append(contentsOf: emoji.text.unicodeScalars.filter { !(0x1F3FB...0x1F3FF).contains($0.value) })
        self = Self.byEmoji[String(plain)] ?? .cheer
    }

    public var description: String { id }
}

extension Emoji {
    /// The emoji bar's six, in the approved order, wherever a member reacts (动态, the 6pm push);
    /// ＋ offers any other.
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

/// How a member reacted.
public enum ReactionGesture: Hashable, Sendable {
    /// Picked an emoji from the bar or the keyboard: the same one again takes it back.
    case pick(Emoji)
    /// Double-tapped the photo: ❤️, which a double tap never takes back.
    case doubleTap
}

/// A member's response changed on a post: the post as it now reads, and what they left before
/// and now (nil when none).
public struct ResponseChange<Kind: Hashable & Sendable>: Hashable, Sendable {
    public let post: FeedPost
    public let now: Kind?
    public let before: Kind?

    /// Whether there is anything to send.
    public var changed: Bool { now != before }
}

extension FeedPost {
    /// The post after `viewer` reacts.
    public func reacting(
        _ gesture: ReactionGesture, by viewer: MemberID, at moment: Timestamp
    ) throws(FeedError) -> ResponseChange<Emoji> {
        guard canRespond(viewer) else { throw .ownPost }
        let before = reactions.kind(of: viewer)
        let now: Emoji? =
            switch gesture {
            case .pick(let emoji): emoji == before ? nil : emoji
            case .doubleTap: .heart
            }
        var post = self
        if now != before { post.reactions = reactions.setting(now, for: viewer, at: moment) }
        return ResponseChange(post: post, now: now, before: before)
    }
}
