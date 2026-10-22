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
/// teammate reacts. A player that doesn't know an id plays `happyHop`.
public struct MoveID: Hashable, Sendable, CustomStringConvertible {
    /// A small hop, arms up: ❤️, and any emoji without a move of its own.
    public static let happyHop = MoveID("happy-hop")

    /// The emoji that have a move of their own; the rest hop. 第一期's fixed table, from the feed
    /// design; 第二期's coach picks moves and falls back to it.
    static let byEmoji: [String: MoveID] = [
        "😂": MoveID("laugh-bend"), "🤣": MoveID("laugh-bend"),
        "💪": MoveID("pump"),
        "🤤": MoveID("drool"), "😋": MoveID("drool"),
        "😮": MoveID("shocked"), "😱": MoveID("shocked"), "😳": MoveID("shocked"),
        "😡": MoveID("pout"), "😤": MoveID("pout"), "💩": MoveID("pout"),
        "🔥": MoveID("clap"), "👏": MoveID("clap"), "🎉": MoveID("clap"),
        "😎": MoveID("chin-up"), "🏆": MoveID("chin-up"), "👑": MoveID("chin-up"),
        "🥹": MoveID("touched"), "🥲": MoveID("touched"), "😭": MoveID("touched"),
        "🤔": MoveID("confused"),
        "🙈": MoveID("shy"), "☺️": MoveID("shy"),
        "👋": MoveID("wave"),
    ]

    public let id: String

    public init(_ id: String) { self.id = id }

    /// The move an emoji makes the author's character play, whatever its skin tone.
    public init(_ emoji: Emoji) {
        var plain = String.UnicodeScalarView()
        plain.append(contentsOf: emoji.text.unicodeScalars.filter { !(0x1F3FB...0x1F3FF).contains($0.value) })
        self = Self.byEmoji[String(plain)] ?? .happyHop
    }

    public var description: String { id }
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
