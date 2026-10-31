import Contracts
import FeedDomain
import Foundation

/// A squad's feed kept in memory, for previews, UI tests and builds that don't talk to the API
/// yet. Reactions are kept as the API keeps them: one emoji per member.
public actor InMemoryFeedSource: FeedSource, MyPostsSource {
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
}

extension InMemoryFeedSource {
    /// The viewer's own posts, newest first, a page at a time; the next page starts past the
    /// post of the id given.
    public func myPosts(kind: PostKind?, after: String?) async throws(FeedError) -> MyPostsPage {
        let mine = posts.filter { $0.checkIn.member == viewer }
            .sorted { ($0.checkIn.day, $0.checkIn.createdAt) > ($1.checkIn.day, $1.checkIn.createdAt) }
        let shown = mine.filter { kind == nil || PostKind($0.checkIn.entry) == kind }
        let start = after.flatMap { id in shown.firstIndex { $0.id.description == id }.map { $0 + 1 } } ?? 0
        let page = Array(shown[min(start, shown.count)..<min(start + Self.page, shown.count)])
        let next = start + Self.page < shown.count ? page.last?.id.description : nil
        let counts =
            after == nil
            ? MyPostCounts(posts: mine.count, reactions: mine.reduce(0) { $0 + $1.reactions.all.count }) : nil
        return MyPostsPage(posts: page, next: next, counts: counts)
    }

    private static let page = 30
}

extension FeedPost {
    /// The post with `member`'s emoji set, or taken back when nil, as the server keeps it.
    fileprivate func reacting(_ emoji: Emoji?, by member: MemberID) throws(FeedError) -> FeedPost {
        guard canRespond(member) else { throw .ownPost }
        let moment = Timestamp(Date())
        return FeedPost(checkIn: checkIn, reactions: reactions.setting(emoji, for: member, at: moment))
    }
}
