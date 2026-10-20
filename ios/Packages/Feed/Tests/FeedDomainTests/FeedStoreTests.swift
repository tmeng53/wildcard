import Contracts
import Testing

@testable import FeedDomain

@MainActor
func store(_ source: FakeSource, viewer: MemberID = coco, today: LocalDay = thursday) -> FeedStore {
    FeedStore(source: source, squad: squad, viewer: viewer, today: { today }, now: { at(500) })
}

let jaysRun = FeedPost(
    checkIn: checkIn(1, by: jay, on: "2026-10-22", at: 100), reactions: reactions([(mia, .cheer, 10)]))
let miasSlip = FeedPost(checkIn: checkIn(2, by: mia, on: "2026-10-21", at: 50, disclaimer: true))

@MainActor @Test func loadsTheLatestWeekInSections() async {
    let source = FakeSource([jaysRun, miasSlip])
    let feed = store(source)
    await feed.load()
    #expect(feed.phase == .current)
    #expect(feed.sections.map(\.heading) == [.today, .yesterday])
    #expect(await source.calls == [.posts(day("2026-10-16"), day("2026-10-23"))])
}

@MainActor @Test func aReactionShowsAtOnceAndGoesOut() async throws {
    let source = FakeSource([jaysRun])
    let feed = store(source)
    await feed.load()
    let move = try feed.react(.pick(.lol), on: jaysRun.id)
    #expect(move == .laugh)
    #expect(feed.post(jaysRun.id)?.reactions.kind(of: coco) == .lol)
    await feed.sendResponses()
    #expect(await source.calls.last == .reaction(.lol, jaysRun.id))
    #expect(feed.post(jaysRun.id)?.reactions.kind(of: coco) == .lol)
}

@MainActor @Test func quickTapsEndOnTheLastOneOnTheServerToo() async throws {
    let source = FakeSource([jaysRun])
    let feed = store(source)
    await feed.load()
    await source.hold()
    try feed.react(.pick(.cheer), on: jaysRun.id)
    let first = Task { await feed.sendResponses() }
    while await source.waiting == 0 { await Task.yield() }
    try feed.react(.pick(.lol), on: jaysRun.id)
    try feed.react(.pick(.highlight), on: jaysRun.id)
    await feed.sendResponses()  // already going out: picks the newest wish up after
    await source.release()
    await first.value
    let sent = await source.calls.dropFirst()
    #expect(Array(sent) == [.reaction(.cheer, jaysRun.id), .reaction(.highlight, jaysRun.id)])
    #expect(feed.post(jaysRun.id)?.reactions.kind(of: coco) == .highlight)
}

@MainActor @Test func aReactionThatCannotGoOutFallsBackToTheServers() async throws {
    let source = FakeSource([jaysRun])
    let feed = store(source, viewer: mia)
    await feed.load()
    try feed.react(.pick(.lol), on: jaysRun.id)
    await source.fail(with: .notSent)
    await feed.sendResponses()
    #expect(feed.post(jaysRun.id)?.reactions.kind(of: mia) == .cheer)
    #expect(feed.failure == .notSent)
    feed.dismissFailure()
    #expect(feed.failure == nil)
}

@MainActor @Test func aRepliedPostThatIsGoneLeavesTheFeed() async throws {
    let source = FakeSource([miasSlip])
    let feed = store(source)
    await feed.load()
    #expect(try feed.reply(.hug, on: miasSlip.id) == .wave)
    await source.fail(with: .postGone)
    await feed.sendResponses()
    #expect(feed.post(miasSlip.id) == nil)
    #expect(feed.failure == .postGone)
}

@MainActor @Test func aResponseOnItsWayOutlivesAReload() async throws {
    let source = FakeSource([miasSlip])
    let feed = store(source)
    await feed.load()
    try feed.reply(.approved, on: miasSlip.id)
    await feed.load()
    #expect(feed.post(miasSlip.id)?.replies.kind(of: coco) == .approved)
}

@MainActor @Test func tappingWhatIsAlreadyThereSendsNothing() async throws {
    let source = FakeSource([jaysRun])
    let feed = store(source, viewer: mia)
    await feed.load()
    #expect(try feed.react(.doubleTap, on: jaysRun.id) == .pump)
    await feed.sendResponses()
    #expect(await source.calls.count == 1)
}

@MainActor @Test func goingBackStopsAfterAMonthOfNothing() async {
    let old = FeedPost(checkIn: checkIn(3, by: jay, on: "2026-10-10"))
    let source = FakeSource([jaysRun, old])
    let feed = store(source)
    await feed.load()
    await feed.loadEarlier()
    #expect(feed.post(old.id) != nil)
    for _ in 0..<FeedStore.emptyWeeksBeforeTheStart { await feed.loadEarlier() }
    #expect(!feed.hasEarlier)
    let loads = await source.calls.count
    await feed.loadEarlier()
    #expect(await source.calls.count == loads)
}

@MainActor @Test func aFailedFirstLoadIsOfflineAndALaterOneKeepsThePosts() async {
    let source = FakeSource([jaysRun], failing: .notSent)
    let feed = store(source)
    await feed.load()
    #expect(feed.phase == .offline)
    await source.fail(with: nil)
    await feed.load()
    await source.fail(with: .notSent)
    await feed.load()
    #expect(feed.phase == .current)
    #expect(feed.post(jaysRun.id) != nil)
}

@MainActor @Test func leavingTheSquadOrSigningOutShowsInThePhase() async {
    let source = FakeSource([], failing: .notInSquad)
    let feed = store(source)
    await feed.load()
    #expect(feed.phase == .notInSquad)
    await source.fail(with: .signedOut)
    await feed.load()
    #expect(feed.phase == .signedOut)
}

@MainActor @Test func reactingToAPostNotLoadedSaysItIsGone() {
    let feed = store(FakeSource([]))
    #expect(throws: FeedError.postGone) { try feed.react(.doubleTap, on: checkInID(42)) }
}
