import Contracts
import Foundation

/// The server, as the feed needs it. The app passes the API adapter (`Backend`), or an in-memory
/// squad for previews and UI tests. `.notSent` means trying again later is safe.
public protocol FeedSource: Sendable {
    /// The squad's check-ins for these days, with each one's reactions.
    func posts(in squad: SquadID, from first: LocalDay, through last: LocalDay) async throws(FeedError) -> [FeedPost]
    /// The squad's members' characters, by member: whose post it is, and who reacted. A member
    /// who hasn't made one yet is missing.
    func characters(in squad: SquadID) async throws(FeedError) -> [MemberID: MemberCharacter]
    /// A post's photo, as JPEG. Nil when it can't be had now; the card shows its place empty.
    func photo(_ ref: PhotoRef) async -> Data?
    /// Sets the member's one emoji on a teammate's check-in, or takes it back when nil. Safe
    /// to repeat.
    func setReaction(_ emoji: Emoji?, on checkIn: CheckInID) async throws(FeedError)
    /// One post as the feed shows it, with its reactions and comments: a post's own page. The
    /// member's own posts load even from a squad they left.
    func post(_ id: CheckInID) async throws(FeedError) -> FeedPost
    /// Writes the member's comment under a post, under the id given: the same again is a retry,
    /// and answers the comment as the server keeps it.
    func comment(_ text: CommentText, id: CommentID, replyingTo member: MemberID?, on checkIn: CheckInID)
        async throws(FeedError) -> Comment
    /// Deletes the member's own comment. Safe to repeat.
    func deleteComment(_ id: CommentID, on checkIn: CheckInID) async throws(FeedError)
}
