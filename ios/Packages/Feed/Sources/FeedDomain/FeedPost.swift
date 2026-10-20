import Contracts

/// One check-in in the feed, with teammates' reactions and, on a 请假条, their replies.
public struct FeedPost: Hashable, Sendable, Identifiable {
    public let checkIn: CheckIn
    public internal(set) var reactions: Responses<ReactionKind>
    /// Always empty on anything but a 请假条.
    public internal(set) var replies: Responses<ReplyKind>

    public init(checkIn: CheckIn, reactions: Responses<ReactionKind> = .init(), replies: Responses<ReplyKind> = .init())
    {
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

/// What the author's character does when a teammate responds: the move lands where everyone
/// sees it, on the post.
public enum CharacterMove: Hashable, Sendable, CaseIterable {
    /// 加油: two fist pumps, a hop on the second.
    case pump
    /// 名场面: crouch, spring, land in a V.
    case pose
    /// 笑死: shakes with laughter, holding its belly.
    case laugh
    /// Any reply on a 请假条: waves the slip in thanks.
    case wave

    public init(_ reaction: ReactionKind) {
        switch reaction {
        case .cheer: self = .pump
        case .highlight: self = .pose
        case .lol: self = .laugh
        }
    }

    public init(_ reply: ReplyKind) {
        self = .wave
    }
}

/// How a member reacted.
public enum ReactionGesture: Hashable, Sendable {
    /// Tapped a reaction, or picked one from the picker: the same one again takes it back.
    case pick(ReactionKind)
    /// Double-tapped the photo: 加油, which a double tap never takes back.
    case doubleTap
}

/// A member's response changed on a post: the post as it now reads, what to send, and the move
/// the author's character plays (none when the member took their response back).
public struct ResponseChange<Kind: Hashable & Sendable>: Hashable, Sendable {
    public let post: FeedPost
    /// The member's response now; nil when taken back.
    public let now: Kind?
    /// Their response before.
    public let before: Kind?
    public let move: CharacterMove?

    /// Whether there is anything to send.
    public var changed: Bool { now != before }
}

extension FeedPost {
    /// The post after `viewer` reacts.
    public func reacting(
        _ gesture: ReactionGesture, by viewer: MemberID, at moment: Timestamp
    ) throws(FeedError) -> ResponseChange<ReactionKind> {
        guard canRespond(viewer) else { throw .ownPost }
        let before = reactions.kind(of: viewer)
        let now: ReactionKind? =
            switch gesture {
            case .pick(let kind): kind == before ? nil : kind
            case .doubleTap: .cheer
            }
        var post = self
        if now != before { post.reactions = reactions.setting(now, for: viewer, at: moment) }
        return ResponseChange(post: post, now: now, before: before, move: now.map(CharacterMove.init))
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
        return ResponseChange(post: post, now: now, before: before, move: now.map(CharacterMove.init))
    }
}
