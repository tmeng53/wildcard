import Contracts
import Testing

@testable import FeedDomain

@Test func aTeammatesPostIsNewsWhenPosted() {
    #expect(jaysRun.latestNews(for: coco) == at(100))
    // Mia's ❤️ on Jay's own post is news to Jay.
    #expect(jaysRun.latestNews(for: jay) == at(10))
    #expect(FeedPost(checkIn: checkIn(5, by: jay, on: "2026-10-22", at: 100)).latestNews(for: jay) == nil)
}

@Test func onMyPostTeammatesReactionsAndCommentsAreNewsButMineArent() {
    let mine = FeedPost(
        checkIn: checkIn(3, by: coco, on: "2026-10-22", at: 100),
        reactions: reactions([(mia, "❤️", 150), (coco, "💪", 400)]),
        comments: [comment(1, by: jay, "冲", at: 200), comment(2, by: coco, "谢谢", replyTo: jay, at: 300)])
    #expect(mine.latestNews(for: coco) == at(200))
}

@Test func onATeammatesPostOnlyARepliesToMeAreNews() {
    let theirs = FeedPost(
        checkIn: checkIn(4, by: jay, on: "2026-10-22", at: 100),
        comments: [
            comment(1, by: coco, "好猛", at: 200), comment(2, by: mia, "同感", at: 250),
            comment(3, by: jay, "哈哈", replyTo: coco, at: 300),
        ])
    #expect(theirs.latestNews(for: coco) == at(300))
    #expect(theirs.latestNews(for: mia) == at(100))
}

@MainActor @Test func theLatestNewsIsReadFromTheServerWithoutChangingTheFeed() async {
    let source = FakeSource([jaysRun, miasSlip])
    let feed = store(source)
    #expect(await feed.latestNewsOnServer() == at(100))
    #expect(feed.sections.isEmpty)
    #expect(feed.latestNews == nil)

    await feed.load()
    #expect(feed.latestNews == at(100))

    await source.fail(with: .notSent)
    #expect(await feed.latestNewsOnServer() == nil)
}
