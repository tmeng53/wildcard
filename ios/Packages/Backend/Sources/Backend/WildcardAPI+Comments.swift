import APIContract
import Contracts

// Comments under a check-in, and one post with its reactions and comments.
extension WildcardAPI {
    /// Writes the member's comment under a check-in they can see, under the id the app picked:
    /// the same comment again is a retry, and answers the one saved.
    public func comment(
        _ text: CommentText, id: CommentID, replyingTo member: MemberID?, on checkIn: CheckInID
    ) async throws(APIError) -> Comment {
        let wire = try await call {
            switch try await client.commentOnCheckIn(
                path: .init(checkInId: checkIn.description, commentId: id.description),
                body: .json(text.draft(replyingTo: member)))
            {
            case .ok(let saved): return try saved.body.json
            case .created(let created): return try created.body.json
            default: throw APIError.unreadableResponse
            }
        }
        return try read { () throws(ContractsError) in try Comment(wire) }
    }

    /// Deletes the member's own comment; fine when it is gone already.
    public func deleteComment(_ id: CommentID, on checkIn: CheckInID) async throws(APIError) {
        try await call {
            _ = try await client.deleteComment(
                path: .init(checkInId: checkIn.description, commentId: id.description)
            ).noContent
        }
    }

    func postWire(_ checkIn: CheckInID) async throws(APIError) -> Components.Schemas.Post {
        try await call { try await client.getPost(path: .init(id: checkIn.description)).ok.body.json }
    }
}
