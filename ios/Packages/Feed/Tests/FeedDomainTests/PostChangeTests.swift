import Contracts
import Testing

@testable import FeedDomain

private let cocosRun = FeedPost(
    checkIn: checkIn(7, by: coco, on: "2026-10-22", at: 120), reactions: reactions([(jay, "💪", 10), (mia, "😂", 20)]),
    comments: [comment(1, by: jay, "腿还在吗")])

/// Coco's run, now a swim: the same id, day and time.
private func asSwim(_ post: FeedPost) -> CheckIn {
    let original = post.checkIn
    return CheckIn(
        id: original.id, member: original.member, day: original.day, createdAt: original.createdAt,
        audience: original.audience, entry: .trained(Training(activity: .sport("swim"))))
}

@MainActor @Test func anEditedPostKeepsItsReactionsAndCommentsInTheFeed() async {
    let feed = store(FakeSource([jaysRun, cocosRun]))
    await feed.load()
    feed.apply(.edited(asSwim(cocosRun)))
    #expect(feed.post(cocosRun.id)?.checkIn == asSwim(cocosRun))
    #expect(feed.post(cocosRun.id)?.reactions == cocosRun.reactions)
    #expect(feed.post(cocosRun.id)?.comments == cocosRun.comments)
    #expect(feed.post(jaysRun.id) == jaysRun)
}

@MainActor @Test func aDeletedPostLeavesTheFeedAndItsDay() async {
    let feed = store(FakeSource([jaysRun, cocosRun, miasSlip]))
    await feed.load()
    feed.apply(.deleted(miasSlip.id))
    #expect(feed.post(miasSlip.id) == nil)
    #expect(feed.sections.map(\.heading) == [.today])
}

@MainActor @Test func aDeletedPostLeavesTheWallAndItsCounts() async {
    let mine = FeedPost(checkIn: checkIn(1, by: member(1), on: "2026-10-22", at: 300))
    let older = FeedPost(
        checkIn: checkIn(2, by: member(1), on: "2026-10-20", at: 200), reactions: reactions([(jay, "🔥", 5)]))
    let wall = PostWallStore(source: FakeWall([mine, older]))
    await wall.load()
    wall.apply(.deleted(older.id))
    #expect(wall.posts == [mine])
    #expect(wall.counts == MyPostCounts(posts: 1, reactions: 2))
}
