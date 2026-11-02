import Contracts
import Foundation
import Testing

@testable import FeedDomain

/// The member's posts in memory, two a page, as the server pages them: the page after `after`
/// starts past the post of that id. Records every call.
actor FakeWall: MyPostsSource {
    struct Call: Equatable {
        let kind: PostKind?
        let after: String?
    }

    private(set) var calls: [Call] = []
    var posts: [FeedPost]
    var failure: FeedError?

    init(_ posts: [FeedPost], failing failure: FeedError? = nil) {
        self.posts = posts
        self.failure = failure
    }

    func fail(with error: FeedError?) { failure = error }

    func myPosts(kind: PostKind?, after: String?) async throws(FeedError) -> MyPostsPage {
        calls.append(Call(kind: kind, after: after))
        if let failure { throw failure }
        let shown = posts.filter { kind == nil || PostKind($0.checkIn.entry) == kind }
        let start = after.flatMap { id in shown.firstIndex { $0.id.description == id }.map { $0 + 1 } } ?? 0
        let page = Array(shown[start..<min(start + 2, shown.count)])
        let next = start + 2 < shown.count ? page.last?.id.description : nil
        let counts = after == nil ? MyPostCounts(posts: posts.count, reactions: 3) : nil
        return MyPostsPage(posts: page, next: next, counts: counts)
    }

    func photo(_ ref: PhotoRef) async -> Data? { nil }
}

private let owner = member(1)
private let octoberRun = FeedPost(checkIn: checkIn(1, by: owner, on: "2026-10-22", at: 300))
private let octoberSlip = FeedPost(checkIn: checkIn(2, by: owner, on: "2026-10-20", at: 200, disclaimer: true))
private let septemberRun = FeedPost(checkIn: checkIn(3, by: owner, on: "2026-09-30", at: 100))

@MainActor @Test func loadsTheNewestPageWithTheCountsInMonths() async {
    let wall = PostWallStore(source: FakeWall([octoberRun, octoberSlip, septemberRun]))
    #expect(wall.phase == .loading)
    await wall.load()
    #expect(wall.phase == .current)
    #expect(wall.counts == MyPostCounts(posts: 3, reactions: 3))
    #expect(wall.months.map(\.id) == [202610])
    #expect(wall.months.first?.posts == [octoberRun, octoberSlip])
    #expect(wall.hasMore)
}

@MainActor @Test func scrollingOnLoadsTheNextPageUntilTheFirstPost() async {
    let source = FakeWall([octoberRun, octoberSlip, septemberRun])
    let wall = PostWallStore(source: source)
    await wall.load()
    await wall.loadMore()
    #expect(wall.months.map(\.id) == [202610, 202609])
    #expect(wall.posts == [octoberRun, octoberSlip, septemberRun])
    #expect(!wall.hasMore)
    #expect(wall.counts == MyPostCounts(posts: 3, reactions: 3))
    await wall.loadMore()
    #expect(
        await source.calls == [.init(kind: nil, after: nil), .init(kind: nil, after: octoberSlip.id.description)])
}

@MainActor @Test func pickingAKindLoadsItFromTheNewest() async {
    let source = FakeWall([octoberRun, octoberSlip, septemberRun])
    let wall = PostWallStore(source: source)
    await wall.load()
    await wall.show(.trained)
    #expect(wall.kind == .trained)
    #expect(wall.posts == [octoberRun, septemberRun])
    #expect(!wall.hasMore)
    await wall.show(nil)
    #expect(wall.posts == [octoberRun, octoberSlip])
    #expect(await source.calls.map(\.kind) == [nil, .trained, nil])
}

@MainActor @Test func offlineFirstSaysSoAndKeepsWhatItHadAfter() async {
    let source = FakeWall([octoberRun], failing: .notSent)
    let wall = PostWallStore(source: source)
    await wall.load()
    #expect(wall.phase == .offline)
    await source.fail(with: nil)
    await wall.load()
    await source.fail(with: .notSent)
    await wall.load()
    #expect(wall.phase == .current)
    #expect(wall.posts == [octoberRun])
    await source.fail(with: .signedOut)
    await wall.load()
    #expect(wall.phase == .signedOut)
}

@MainActor @Test func aFailedPageSaysSoAndTriesAgainFromTheSamePlace() async {
    let source = FakeWall([octoberRun, octoberSlip, septemberRun])
    let wall = PostWallStore(source: source)
    await wall.load()
    await source.fail(with: .notSent)
    await wall.loadMore()
    #expect(wall.moreFailed)
    #expect(wall.posts == [octoberRun, octoberSlip])
    #expect(wall.hasMore)
    await source.fail(with: nil)
    await wall.loadMore()
    #expect(!wall.moreFailed)
    #expect(wall.posts == [octoberRun, octoberSlip, septemberRun])
    #expect(
        await source.calls.map(\.after) == [nil, octoberSlip.id.description, octoberSlip.id.description])
}

@MainActor @Test func pickingAKindClearsAFailedPage() async {
    let source = FakeWall([octoberRun, octoberSlip, septemberRun])
    let wall = PostWallStore(source: source)
    await wall.load()
    await source.fail(with: .notSent)
    await wall.loadMore()
    await source.fail(with: nil)
    await wall.show(.trained)
    #expect(!wall.moreFailed)
    #expect(wall.posts == [octoberRun, septemberRun])
}

@Test func monthsKeepThePostsOrderAndSplitAtEachNewMonth() {
    let months = WallMonth.months([octoberRun, octoberSlip, septemberRun])
    #expect(months.map(\.year) == [2026, 2026])
    #expect(months.map(\.month) == [10, 9])
    #expect(months.map(\.posts.count) == [2, 1])
}
