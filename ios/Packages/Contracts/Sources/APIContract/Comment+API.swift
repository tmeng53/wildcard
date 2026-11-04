import Contracts

extension Comment {
    public init(_ wire: Components.Schemas.CommentEntry) throws(ContractsError) {
        self.init(
            id: try CommentID(wire: wire.id), member: try MemberID(wire: wire.member),
            text: try CommentText(wire.text),
            replyTo: try ReplyTarget(member: wire.replyTo, coach: wire.replyToCoach),
            commentedAt: Timestamp(wire: wire.commentedAt))
    }

    public init(_ wire: Components.Schemas.Comment) throws(ContractsError) {
        self.init(
            id: try CommentID(wire: wire.id), member: try MemberID(wire: wire.member),
            text: try CommentText(wire.text),
            replyTo: try ReplyTarget(member: wire.replyTo, coach: wire.replyToCoach),
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

extension CommentText {
    /// The body of `PUT /check-ins/{checkInId}/comments/{commentId}`.
    public func draft(replyingTo target: ReplyTarget?) -> Components.Schemas.CommentDraft {
        switch target {
        case .member(let member): .init(version: ._1, text: text, replyTo: member.description)
        case .coach(let coach): .init(version: ._1, text: text, replyToCoach: coach.rawValue)
        case nil: .init(version: ._1, text: text)
        }
    }
}
