#if os(iOS)
import Contracts
import FeedDomain

// A post's own page.
extension FeedModel {
    /// Opens a post's own page, where its comments are: from its card, or from a comment's push.
    public func openPage(_ post: CheckInID) {
        // Already open (a comment's push while reading it): read it again for the new comment.
        if opened == post { Task { await store.loadPost(post) } }
        closeBar()
        listing = nil
        replyingTo = nil
        opened = post
    }

    /// Reads a post's page again when news of it comes while it is open (the coach answered, a
    /// teammate commented), so the page shows it without a pull.
    public func refreshIfOpen(about notice: Notice) {
        if let opened { refresh(opened, about: notice) }
    }

    /// Reads `post`'s page again when `notice` is news of it, for a page shown with its own model
    /// (opened from 通知, a push, 我的动态 or 训练记录).
    public func refresh(_ post: CheckInID, about notice: Notice) {
        guard case .post(let about) = notice.destination, about == post else { return }
        Task { await loadPage(post) }
    }

    /// A post's own page outside the feed (a tile on 我的动态): one post, read and answered as
    /// 动态 does, with the same recent emoji.
    public func page(of post: CheckInID) -> FeedModel {
        let page = FeedModel(
            store: store.store(of: post), viewer: viewer, editor: editor, coach: coach, places: places, now: now,
            defaults: defaults)
        page.changed = { [weak self] change in
            self?.store.apply(change)
            self?.changed?(change)
        }
        // A tag on the page opens the card as 动态 does, whenever 动态 set that up.
        page.openTeammate = { [weak self] member in self?.openTeammate(member) }
        page.squadName = { [weak self] in self?.squadName() }
        return page
    }

    /// A tagged place's page in the member's squad; nil where the app has no pages of places, or
    /// for a place without a key.
    public func placePage(_ place: Place) -> PlacePageStore? {
        guard let places, let key = place.key, let squad = store.squad else { return nil }
        return PlacePageStore(book: places, squad: squad, place: place, key: key)
    }

    /// Sends the member's comment on a post, replying to whomever they picked and @-ing
    /// `mentions`. False when it couldn't go out; the words stay to try again.
    func comment(_ text: CommentText, mentioning mentions: Mentions = .none, on post: CheckInID) async -> Bool {
        let target = replyingTo
        let sent = await store.comment(text, replyingTo: target, mentioning: mentions, on: post)
        if sent {
            if replyingTo == target { replyingTo = nil }
            commentsSent += 1
            // The coach's answer may already be there; if not, its notice reads the page again.
            if case .coach = target {
                await coach?.load(about: [post])
            } else if mentions.coach != nil {
                await coach?.load(about: [post])
            }
        }
        return sent
    }
}
#endif
