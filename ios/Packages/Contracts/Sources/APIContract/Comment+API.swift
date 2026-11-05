import Contracts

extension Comment {
    public init(_ wire: Components.Schemas.CommentEntry) throws(ContractsError) {
        self.init(
            id: try CommentID(wire: wire.id), member: try MemberID(wire: wire.member),
            text: try CommentText(wire.text),
            replyTo: try ReplyTarget(member: wire.replyTo, coach: wire.replyToCoach),
            mentions: try Mentions(members: wire.mentions, coach: wire.mentionsCoach),
            commentedAt: Timestamp(wire: wire.commentedAt))
    }

    public init(_ wire: Components.Schemas.Comment) throws(ContractsError) {
        self.init(
            id: try CommentID(wire: wire.id), member: try MemberID(wire: wire.member),
            text: try CommentText(wire.text),
            replyTo: try ReplyTarget(member: wire.replyTo, coach: wire.replyToCoach),
            mentions: try Mentions(members: wire.mentions, coach: wire.mentionsCoach),
            commentedAt: Timestamp(wire: wire.commentedAt))
    }
}

extension ReplyTarget {
    /// From a comment's `replyTo` and `replyToCoach`; nil when it has neither.
    init?(member: String?, coach: String?) throws(ContractsError) {
        if let member {
            self = .member(try MemberID(wire: member))
        } else if let coach {
            guard let id = CoachID(rawValue: coach) else { throw .invalidCoachID(coach) }
            self = .coach(id)
        } else {
            return nil
        }
    }
}

extension Mentions {
    /// From a comment's `mentions` and `mentionsCoach`.
    init(members: [String]?, coach: String?) throws(ContractsError) {
        var ids: [MemberID] = []
        for member in members ?? [] { ids.append(try MemberID(wire: member)) }
        var coachID: CoachID?
        if let coach {
            guard let id = CoachID(rawValue: coach) else { throw .invalidCoachID(coach) }
            coachID = id
        }
        self.init(members: ids, coach: coachID)
    }
}

extension CommentText {
    /// The body of `PUT /check-ins/{checkInId}/comments/{commentId}`.
    public func draft(replyingTo target: ReplyTarget?, mentioning mentions: Mentions = .none)
        -> Components.Schemas.CommentDraft
    {
        var draft = Components.Schemas.CommentDraft(version: ._1, text: text)
        switch target {
        case .member(let member): draft.replyTo = member.description
        case .coach(let coach): draft.replyToCoach = coach.rawValue
        case nil: break
        }
        if !mentions.members.isEmpty { draft.mentions = mentions.members.map(\.description) }
        draft.mentionsCoach = mentions.coach?.rawValue
        return draft
    }
}
