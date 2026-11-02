import Contracts

extension Comment {
    public init(_ wire: Components.Schemas.CommentEntry) throws(ContractsError) {
        self.init(
            id: try CommentID(wire: wire.id), member: try MemberID(wire: wire.member),
            text: try CommentText(wire.text),
            replyTo: try wire.replyTo.map { id throws(ContractsError) in
                try MemberID(wire: id)
            }, commentedAt: Timestamp(wire: wire.commentedAt))
    }

    public init(_ wire: Components.Schemas.Comment) throws(ContractsError) {
        self.init(
            id: try CommentID(wire: wire.id), member: try MemberID(wire: wire.member),
            text: try CommentText(wire.text),
            replyTo: try wire.replyTo.map { id throws(ContractsError) in
                try MemberID(wire: id)
            }, commentedAt: Timestamp(wire: wire.commentedAt))
    }
}

extension CommentText {
    /// The body of `PUT /check-ins/{checkInId}/comments/{commentId}`.
    public func draft(replyingTo member: MemberID?) -> Components.Schemas.CommentDraft {
        .init(version: ._1, text: text, replyTo: member?.description)
    }
}
