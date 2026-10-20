import Contracts

/// One check-in in the feed, with teammates' emoji and, on a 请假条, their replies.
public struct FeedPost: Hashable, Sendable, Identifiable {
    public let checkIn: CheckIn
    public internal(set) var reactions: Responses<Emoji>
    /// Always empty on anything but a 请假条.
    public internal(set) var replies: Responses<ReplyKind>

    public init(checkIn: CheckIn, reactions: Responses<Emoji> = .init(), replies: Responses<ReplyKind> = .init()) {
        self.checkIn = checkIn
        self.reactions = reactions
        self.replies = checkIn.takesReplies ? replies : .init()
    }

    public var id: CheckInID { checkIn.id }
    public var author: MemberID { checkIn.member }

    /// Only a 请假条 gets replies.
    public var takesReplies: Bool { checkIn.takesReplies }

    /// Teammates respond; nobody responds to their own post.
    public func canRespond(_ viewer: MemberID) -> Bool { viewer != author }
}

extension CheckIn {
    fileprivate var takesReplies: Bool {
        if case .disclaimer = entry { true } else { false }
    }
}

/// A move from the character's move library, by id, which the author's character plays when a
/// teammate responds. The server picks the move for an emoji; the ids are data, so a new move
/// needs no change here, and a player that doesn't know one plays `happyHop`.
public struct MoveID: Hashable, Sendable, CustomStringConvertible {
    /// The small hop, arms up, played when the server's pick is late or unknown.
    public static let happyHop = MoveID("happy-hop")
    /// Waving the slip in thanks, for any reply on a 请假条.
    public static let wave = MoveID("wave")

    public let id: String

    public init(_ id: String) { self.id = id }

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

    /// The post after `viewer` taps a reply: the same reply again takes it back.
    public func replying(
        _ kind: ReplyKind, by viewer: MemberID, at moment: Timestamp
    ) throws(FeedError) -> ResponseChange<ReplyKind> {
        guard takesReplies else { throw .notADisclaimer }
        guard canRespond(viewer) else { throw .ownPost }
        let before = replies.kind(of: viewer)
        let now: ReplyKind? = kind == before ? nil : kind
        var post = self
        post.replies = replies.setting(now, for: viewer, at: moment)
        return ResponseChange(post: post, now: now, before: before)
    }
}
