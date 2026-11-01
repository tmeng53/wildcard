import Contracts
import Testing

@testable import FeedDomain

@MainActor @Test func aCommentShowsAtOnceAndStaysOnceTheServerTakesIt() async {
    let source = FakeSource([jaysRun])
    let feed = store(source)
    await feed.load()
    await source.hold()
    let sent = Task { await feed.comment(text("明天一起"), replyingTo: jay, on: jaysRun.id) }
    while await source.waiting == 0 { await Task.yield() }
    #expect(feed.post(jaysRun.id)?.comments.map(\.text.text) == ["明天一起"])
    await source.release()
    #expect(await sent.value)
    #expect(feed.post(jaysRun.id)?.comments == [comment(1, by: coco, "明天一起", replyTo: jay, at: 900)])
    #expect(await source.calls.last == .comment(commentID(1), "明天一起", jay, jaysRun.id))
}

@MainActor @Test func aCommentThatCantGoOutLeavesAndSaysWhy() async {
    let source = FakeSource([jaysRun])
    let feed = store(source)
    await feed.load()
    await source.fail(with: .notSent)
    #expect(await feed.comment(text("加油"), replyingTo: nil, on: jaysRun.id) == false)
    #expect(feed.post(jaysRun.id)?.comments == [])
    #expect(feed.failure == .notSent)
}

@MainActor @Test func aDeletedCommentGoesAtOnceAndComesBackWhenRefused() async {
    let mine = comment(7, by: coco, "删掉我")
    let post = FeedPost(checkIn: jaysRun.checkIn, comments: [comment(6, by: jay, "第一"), mine])
    let source = FakeSource([post])
    let feed = store(source)
    await feed.load()

    await source.fail(with: .refused)
    await feed.deleteComment(mine.id, on: post.id)
    #expect(feed.post(post.id)?.comments.map(\.id) == [commentID(6), commentID(7)])
    #expect(feed.failure == .refused)

    await source.fail(with: nil)
    await feed.deleteComment(mine.id, on: post.id)
    #expect(feed.post(post.id)?.comments.map(\.id) == [commentID(6)])
}

@MainActor @Test func theCardShowsTheLatestTwoComments() {
    let post = FeedPost(
        checkIn: jaysRun.checkIn,
        comments: [comment(1, by: jay, "一"), comment(2, by: mia, "二"), comment(3, by: coco, "三")])
    #expect(post.commentsOnCard.map(\.text.text) == ["二", "三"])
}

@MainActor @Test func aStoreOfOnePostLoadsJustThatPostAndItsSquad() async {
    let source = FakeSource([jaysRun, miasSlip])
    let feed = FeedStore(
        source: source, post: miasSlip.id, viewer: coco, today: { thursday }, now: { at(500) },
        newCommentID: { commentID(1) })
    await feed.loadPost(miasSlip.id)
    #expect(feed.phase == .current)
    #expect(feed.post(miasSlip.id) == miasSlip)
    #expect(feed.post(jaysRun.id) == nil)
    #expect(feed.hasEarlier == false)
    #expect(await source.calls == [.post(miasSlip.id)])
}

@MainActor @Test func openingAPostsPageInTheFeedPicksUpNewComments() async {
    let source = FakeSource([jaysRun])
    let feed = store(source)
    await feed.load()
    let later = FeedPost(checkIn: jaysRun.checkIn, reactions: jaysRun.reactions, comments: [comment(2, by: mia, "来了")])
    await source.setPosts([later])
    await feed.loadPost(jaysRun.id)
    #expect(feed.post(jaysRun.id)?.comments.map(\.text.text) == ["来了"])
}

/// Hands out commentID(1), commentID(2), … in turn.
private final class CommentIDs: @unchecked Sendable {
    // Only the main-actor store under test calls it, one call at a time.
    private var next = 0
    func callAsFunction() -> CommentID {
        next += 1
        return commentID(next)
    }
}

@MainActor @Test func sendingTheSameWordsAgainAfterAFailureReusesTheirIDSoTheServerSavesOnce() async {
    let source = FakeSource([jaysRun])
    let ids = CommentIDs()
    let feed = FeedStore(
        source: source, squad: squad, viewer: coco, today: { thursday }, now: { at(500) },
        newCommentID: { ids() })
    await feed.load()
    await source.fail(with: .notSent)
    #expect(await feed.comment(text("加油"), replyingTo: jay, on: jaysRun.id) == false)
    await source.fail(with: nil)
    #expect(await feed.comment(text("加油"), replyingTo: jay, on: jaysRun.id))
    #expect(await feed.comment(text("再来"), replyingTo: jay, on: jaysRun.id))
    #expect(
        await source.calls.suffix(3) == [
            .comment(commentID(1), "加油", jay, jaysRun.id),
            .comment(commentID(1), "加油", jay, jaysRun.id),
            .comment(commentID(2), "再来", jay, jaysRun.id),
        ])
}

@MainActor @Test func otherWordsAfterAFailureAreANewComment() async {
    let source = FakeSource([jaysRun])
    let ids = CommentIDs()
    let feed = FeedStore(
        source: source, squad: squad, viewer: coco, today: { thursday }, now: { at(500) },
        newCommentID: { ids() })
    await feed.load()
    await source.fail(with: .notSent)
    _ = await feed.comment(text("加油"), replyingTo: nil, on: jaysRun.id)
    await source.fail(with: nil)
    _ = await feed.comment(text("加油"), replyingTo: jay, on: jaysRun.id)
    #expect(await source.calls.last == .comment(commentID(2), "加油", jay, jaysRun.id))
}

@MainActor @Test func aCommentInFlightThatAReloadAlreadyListsShowsOnce() async {
    let source = FakeSource([jaysRun])
    let feed = store(source)
    await feed.load()
    await source.hold()
    let sent = Task { await feed.comment(text("明天一起"), replyingTo: nil, on: jaysRun.id) }
    while await source.waiting == 0 { await Task.yield() }
    let saved = FeedPost(
        checkIn: jaysRun.checkIn, reactions: jaysRun.reactions, comments: [comment(1, by: coco, "明天一起", at: 900)])
    await source.setPosts([saved])
    await feed.loadPost(jaysRun.id)
    #expect(feed.post(jaysRun.id)?.comments.map(\.id) == [commentID(1)])
    await source.release()
    #expect(await sent.value)
    #expect(feed.post(jaysRun.id)?.comments.map(\.id) == [commentID(1)])
}

@MainActor @Test func theMembersOwnPostNotSavedYetStaysWhenItsPageOpensOrTakesAComment() async {
    let mine = checkIn(9, by: coco, on: "2026-10-22", at: 400)
    let source = FakeSource([])
    let feed = store(source)
    await feed.load()
    feed.show(mine)
    await feed.loadPost(mine.id)
    #expect(feed.post(mine.id) == FeedPost(checkIn: mine))
    #expect(await feed.comment(text("加油"), replyingTo: nil, on: mine.id) == false)
    #expect(feed.failure == .notSent)
    #expect(feed.post(mine.id) == FeedPost(checkIn: mine))
}

@MainActor @Test func aCommentStillGoingOutCantBeDeletedYet() async {
    let source = FakeSource([jaysRun])
    let feed = store(source)
    await feed.load()
    await source.hold()
    let sent = Task { await feed.comment(text("等等"), replyingTo: nil, on: jaysRun.id) }
    while await source.waiting == 0 { await Task.yield() }
    #expect(feed.isSending(commentID(1), on: jaysRun.id))
    await feed.deleteComment(commentID(1), on: jaysRun.id)
    #expect(feed.post(jaysRun.id)?.comments.map(\.id) == [commentID(1)])
    await source.release()
    #expect(await sent.value)
    #expect(feed.isSending(commentID(1), on: jaysRun.id) == false)
    #expect(await source.calls.contains(.deleteComment(commentID(1), jaysRun.id)) == false)
}

@MainActor @Test func aPageOfOnePostThatIsGoneStopsLoading() async {
    let source = FakeSource([jaysRun])
    let feed = FeedStore(
        source: source, post: miasSlip.id, viewer: coco, today: { thursday }, now: { at(500) },
        newCommentID: { commentID(1) })
    await feed.loadPost(miasSlip.id)
    #expect(feed.phase == .current)
    #expect(feed.post(miasSlip.id) == nil)
}
