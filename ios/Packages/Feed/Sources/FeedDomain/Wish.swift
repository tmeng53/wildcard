import Contracts

/// The reaction the member wants on a post, or none.
struct Wish: Hashable, Sendable {
    let emoji: Emoji?
    let since: Timestamp

    func applied(to post: FeedPost, by member: MemberID) -> FeedPost {
        var post = post
        post.reactions = post.reactions.setting(emoji, for: member, at: since)
        return post
    }
}
