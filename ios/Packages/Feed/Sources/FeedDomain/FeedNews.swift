import Contracts

extension FeedPost {
    /// When this post last had news for `viewer`, the 动态 tab's dot: a teammate posting it, or,
    /// on the viewer's own post, a teammate's reaction or comment, or anywhere a teammate's reply
    /// to the viewer. Nil when it holds none.
    public func latestNews(for viewer: MemberID) -> Timestamp? {
        var moments: [Timestamp] = []
        if author != viewer { moments.append(checkIn.createdAt) }
        for comment in comments where comment.member != viewer && (author == viewer || comment.replyToMember == viewer)
        {
            moments.append(comment.commentedAt)
        }
        if author == viewer {
            moments += reactions.all.filter { $0.member != viewer }.map(\.moment)
        }
        return moments.max()
    }
}
