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
