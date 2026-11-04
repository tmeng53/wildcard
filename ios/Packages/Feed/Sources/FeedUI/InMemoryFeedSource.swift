import Contracts
import FeedDomain
import Foundation

/// A squad's feed kept in memory, for previews, UI tests and builds that don't talk to the API
/// yet. Reactions and comments are kept as the API keeps them: one emoji per member, comments
/// deleted only by their writer.
public actor InMemoryFeedSource: FeedSource, MyPostsSource, CoachSource {
    private let viewer: MemberID
    private var posts: [FeedPost]
    private let characters: [MemberID: MemberCharacter]
    private var photos: [String: Data]
    /// What the squad's coach said; nil for a squad without one.
    private var coach: CoachActivity?

    public init(
        viewer: MemberID, posts: [FeedPost], characters: [MemberID: MemberCharacter], photos: [String: Data] = [:],
        coach: CoachActivity? = nil
    ) {
        self.viewer = viewer
        self.posts = posts
        self.characters = characters
        self.photos = photos
        self.coach = coach
    }

    public func activity(in squad: SquadID, about checkIns: [CheckInID]) async throws(FeedError) -> CoachActivity {
        CoachActivity(
            note: coach?.note, replies: coach?.replies.filter { checkIns.contains($0.checkIn) } ?? [],
            answers: coach?.answers.filter { checkIns.contains($0.checkIn) } ?? [])
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

    public func comment(_ text: CommentText, id: CommentID, replyingTo target: ReplyTarget?, on checkIn: CheckInID)
        async throws(FeedError) -> Comment
    {
        guard let index = posts.firstIndex(where: { $0.id == checkIn }) else { throw .postGone }
        if let saved = posts[index].comments.first(where: { $0.id == id }) { return saved }
        let comment = Comment(id: id, member: viewer, text: text, replyTo: target, commentedAt: Timestamp(Date()))
        let post = posts[index]
        posts[index] = FeedPost(checkIn: post.checkIn, reactions: post.reactions, comments: post.comments + [comment])
        if case .coach(let id) = target { answer(comment, on: checkIn, by: id) }
        return comment
    }

    /// The sample coach answers a reply to it at once, as the API has it answer before the reply
    /// is saved.
    private func answer(_ comment: Comment, on checkIn: CheckInID, by id: CoachID) {
        guard let coach, let speaker = coach.replies.first(where: { $0.coach.id == id })?.coach else { return }
        let answer = CoachAnswer(
            checkIn: checkIn, comment: comment.id, coach: speaker, text: Self.localized("收到，下次带你一起练"),
            writtenAt: Date())
        self.coach = CoachActivity(note: coach.note, replies: coach.replies, answers: coach.answers + [answer])
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

extension InMemoryFeedSource {
    /// Puts the viewer's edited post in place of what it was, with any photo just added, by path.
    func replace(_ checkIn: CheckIn, adding added: [String: Data]) throws(FeedError) {
        guard let index = posts.firstIndex(where: { $0.id == checkIn.id }) else { throw .postGone }
        guard posts[index].checkIn.member == viewer else { throw .refused }
        photos.merge(added) { _, new in new }
        posts[index] = posts[index].applying(.edited(checkIn)) ?? posts[index]
    }

    /// Deletes the viewer's post, with its reactions and comments; one already gone is fine.
    func delete(_ id: CheckInID) throws(FeedError) {
        guard let post = posts.first(where: { $0.id == id }) else { return }
        guard post.checkIn.member == viewer else { throw .refused }
        posts.removeAll { $0.id == id }
    }

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
        return FeedPost(
            checkIn: checkIn, reactions: reactions.setting(emoji, for: member, at: moment), comments: comments)
    }
}
