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

    /// A post's own page outside the feed (a tile on 我的动态): one post, read and answered as
    /// 动态 does, with the same recent emoji.
    public func page(of post: CheckInID) -> FeedModel {
        let page = FeedModel(
            store: store.store(of: post), viewer: viewer, editor: editor, coach: coach, now: now, defaults: defaults)
        page.changed = { [weak self] change in
            self?.store.apply(change)
            self?.changed?(change)
        }
        return page
    }

    /// Sends the member's comment on a post, replying to whomever they picked. False when it
    /// couldn't go out; the words stay to try again.
    func comment(_ text: CommentText, on post: CheckInID) async -> Bool {
        let target = replyingTo
        let sent = await store.comment(text, replyingTo: target, on: post)
        if sent {
            if replyingTo == target { replyingTo = nil }
            commentsSent += 1
            // The server has the coach answer before it answers us, so its answer is there now.
            if case .coach = target { await coach?.load(about: [post]) }
        }
        return sent
    }
}
#endif
