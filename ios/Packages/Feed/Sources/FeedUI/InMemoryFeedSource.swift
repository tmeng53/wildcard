import Contracts
import FeedDomain
import Foundation

/// A squad's feed kept in memory, for previews, UI tests and builds that don't talk to the API
/// yet. Reactions and comments are kept as the API keeps them: one emoji per member, comments
/// deleted only by their writer.
public actor InMemoryFeedSource: FeedSource {
    private let viewer: MemberID
    private var posts: [FeedPost]
    private let characters: [MemberID: MemberCharacter]
    private let photos: [String: Data]

    public init(
        viewer: MemberID, posts: [FeedPost], characters: [MemberID: MemberCharacter], photos: [String: Data] = [:]
    ) {
        self.viewer = viewer
        self.posts = posts
        self.characters = characters
        self.photos = photos
    }

    public func posts(in squad: SquadID, from first: LocalDay, through last: LocalDay) async throws(FeedError)
        -> [FeedPost]
    {
        posts.filter { $0.checkIn.audience.squads.contains(squad) && (first...last).contains($0.checkIn.day) }
    }

    public func characters(in squad: SquadID) async throws(FeedError) -> [MemberID: MemberCharacter] {
        characters
    }

    public func photo(_ ref: PhotoRef) async -> Data? {
        photos[ref.path]
    }

    public func setReaction(_ emoji: Emoji?, on checkIn: CheckInID) async throws(FeedError) {
        guard let index = posts.firstIndex(where: { $0.id == checkIn }) else { throw .postGone }
        posts[index] = try posts[index].reacting(emoji, by: viewer)
    }

    public func post(_ id: CheckInID) async throws(FeedError) -> FeedPost {
        guard let post = posts.first(where: { $0.id == id }) else { throw .postGone }
        return post
    }

    public func comment(_ text: CommentText, id: CommentID, replyingTo member: MemberID?, on checkIn: CheckInID)
        async throws(FeedError) -> Comment
    {
        guard let index = posts.firstIndex(where: { $0.id == checkIn }) else { throw .postGone }
        if let saved = posts[index].comments.first(where: { $0.id == id }) { return saved }
        let comment = Comment(id: id, member: viewer, text: text, replyTo: member, commentedAt: Timestamp(Date()))
        let post = posts[index]
        posts[index] = FeedPost(checkIn: post.checkIn, reactions: post.reactions, comments: post.comments + [comment])
        return comment
    }

    public func deleteComment(_ id: CommentID, on checkIn: CheckInID) async throws(FeedError) {
        guard let index = posts.firstIndex(where: { $0.id == checkIn }) else { throw .postGone }
        let post = posts[index]
        guard let comment = post.comments.first(where: { $0.id == id }) else { return }
        guard comment.member == viewer else { throw .refused }
        posts[index] = FeedPost(
            checkIn: post.checkIn, reactions: post.reactions, comments: post.comments.filter { $0.id != id })
    }
}

extension FeedPost {
    /// The post with `member`'s emoji set, or taken back when nil, as the server keeps it.
    fileprivate func reacting(_ emoji: Emoji?, by member: MemberID) throws(FeedError) -> FeedPost {
        guard canRespond(member) else { throw .ownPost }
        let moment = Timestamp(Date())
        return FeedPost(
            checkIn: checkIn, reactions: reactions.setting(emoji, for: member, at: moment), comments: comments)
    }
}
