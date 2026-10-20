import Contracts

/// The server, as the feed needs it. The app passes the API adapter (`Backend`), or an in-memory
/// squad for previews and UI tests. `.notSent` means trying again later is safe.
public protocol FeedSource: Sendable {
    /// The squad's check-ins for these days, with each one's reactions and replies.
    func posts(in squad: SquadID, from first: LocalDay, through last: LocalDay) async throws(FeedError) -> [FeedPost]
    /// Sets the member's one reaction on a teammate's check-in, or takes it back when nil.
    /// Safe to repeat.
    func setReaction(_ kind: ReactionKind?, on checkIn: CheckInID) async throws(FeedError)
    /// Sets the member's one reply on a teammate's 请假条, or takes it back when nil. Safe to
    /// repeat.
    func setReply(_ kind: ReplyKind?, on checkIn: CheckInID) async throws(FeedError)
}
