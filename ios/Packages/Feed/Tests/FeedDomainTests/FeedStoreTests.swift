import Contracts
import Testing

@testable import FeedDomain

@MainActor
func store(_ source: FakeSource, viewer: MemberID = coco, today: LocalDay = thursday) -> FeedStore {
    FeedStore(
        source: source, squad: squad, viewer: viewer, today: { today }, now: { at(500) },
        newCommentID: { commentID(1) })
}

let jaysRun = FeedPost(checkIn: checkIn(1, by: jay, on: "2026-10-22", at: 100), reactions: reactions([(mia, "❤️", 10)]))
let miasSlip = FeedPost(checkIn: checkIn(2, by: mia, on: "2026-10-21", at: 50, disclaimer: true))

@MainActor @Test func loadsTheLatestWeekInSections() async {
    let source = FakeSource([jaysRun, miasSlip])
    let feed = store(source)
    await feed.load()
    #expect(feed.phase == .current)
    #expect(feed.sections.map(\.heading) == [.today, .yesterday])
    #expect(await source.calls == [.posts(day("2026-10-16"), day("2026-10-23"))])
}

@MainActor @Test func anEmojiShowsAtOnceWithItsMoveAndGoesOut() async throws {
    let source = FakeSource([jaysRun])
    let feed = store(source)
    await feed.load()
    #expect(try feed.react(.pick(emoji("😂")), on: jaysRun.id) == MoveID("laugh-bend"))
    #expect(feed.post(jaysRun.id)?.reactions.kind(of: coco) == emoji("😂"))
    await feed.sendResponses()
    #expect(await source.calls.last == .reaction(emoji("😂"), jaysRun.id))
    #expect(feed.post(jaysRun.id)?.reactions.kind(of: coco) == emoji("😂"))
}

@MainActor @Test func takingAnEmojiBackPlaysNothing() async throws {
    let source = FakeSource([jaysRun])
    let feed = store(source, viewer: mia)
    await feed.load()
    #expect(try feed.react(.pick(.heart), on: jaysRun.id) == nil)
    await feed.sendResponses()
    #expect(await source.calls.last == .reaction(nil, jaysRun.id))
    #expect(feed.post(jaysRun.id)?.reactions.isEmpty == true)
}

@MainActor @Test func quickTapsEndOnTheLastOneOnTheServerToo() async throws {
    let source = FakeSource([jaysRun])
    let feed = store(source)
    await feed.load()
    await source.hold()
    try feed.react(.pick(.heart), on: jaysRun.id)
    let sending = Task { await feed.sendResponses() }
    while await source.waiting == 0 { await Task.yield() }
    try feed.react(.pick(emoji("😂")), on: jaysRun.id)
    try feed.react(.pick(emoji("💪")), on: jaysRun.id)
    await feed.sendResponses()  // already going out: picks the newest wish up after
    await source.release()
    await sending.value
    let sent = await source.calls.dropFirst()
    #expect(Array(sent) == [.reaction(.heart, jaysRun.id), .reaction(emoji("💪"), jaysRun.id)])
    #expect(feed.post(jaysRun.id)?.reactions.kind(of: coco) == emoji("💪"))
}

@MainActor @Test func anEmojiThatCannotGoOutFallsBackToTheServers() async throws {
    let source = FakeSource([jaysRun])
    let feed = store(source, viewer: mia)
    await feed.load()
    try feed.react(.pick(emoji("😂")), on: jaysRun.id)
    await source.fail(with: .notSent)
    await feed.sendResponses()
    #expect(feed.post(jaysRun.id)?.reactions.kind(of: mia) == .heart)
    #expect(feed.failure == .notSent)
    feed.dismissFailure()
    #expect(feed.failure == nil)
}

@MainActor @Test func aReactedPostThatIsGoneLeavesTheFeed() async throws {
    let source = FakeSource([miasSlip])
    let feed = store(source)
    await feed.load()
    try feed.react(.doubleTap, on: miasSlip.id)
    await source.fail(with: .postGone)
    await feed.sendResponses()
    #expect(feed.post(miasSlip.id) == nil)
    #expect(feed.failure == .postGone)
}

@MainActor @Test func anEmojiOnItsWayOutlivesAReload() async throws {
    let source = FakeSource([miasSlip])
    let feed = store(source)
    await feed.load()
    try feed.react(.pick(emoji("🥹")), on: miasSlip.id)
    await feed.load()
    #expect(feed.post(miasSlip.id)?.reactions.kind(of: coco) == emoji("🥹"))
}

@MainActor @Test func doubleTappingAHeartAlreadyThereHopsAndSendsNothing() async throws {
    let source = FakeSource([jaysRun])
    let feed = store(source, viewer: mia)
    await feed.load()
    #expect(try feed.react(.doubleTap, on: jaysRun.id) == MoveID("heart"))
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

@MainActor @Test func aQuietWeekStillShowsTheSquadsLastPosts() async throws {
    let old = FeedPost(checkIn: checkIn(9, by: mia, on: "2026-09-20"))
    let source = FakeSource([old])
    let feed = store(source)
    await feed.load()
    #expect(feed.post(old.id) != nil)
}

@MainActor @Test func aSquadThatNeverPostedStopsLookingBack() async {
    let source = FakeSource([])
    let feed = store(source)
    await feed.load()
    #expect(feed.sections.isEmpty)
    #expect(!feed.hasEarlier)
    #expect(await source.calls.count == 1 + FeedStore.emptyWeeksBeforeTheStart)
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

@MainActor @Test func loadsWhoIsWho() async throws {
    let source = FakeSource([jaysRun])
    let jays = MemberCharacter(
        nickname: try Nickname("阿杰"), look: CharacterLook(persona: "energetic", variants: ["body": "peach"]))
    await source.setCharacters([jay: jays])
    let feed = store(source)
    await feed.load()
    #expect(feed.characters == [jay: jays])
}

@MainActor @Test func myNewPostShowsBeforeTheServerListsItAndOnce() async {
    let source = FakeSource([jaysRun])
    let feed = store(source)
    await feed.load()
    let mine = checkIn(3, by: coco, on: "2026-10-22", at: 400)
    feed.show(mine)
    feed.show(checkIn(4, by: jay, on: "2026-10-22", at: 450))  // only the member's own
    #expect(feed.sections.first?.posts.map(\.id) == [mine.id, jaysRun.id])
    await feed.load()
    #expect(feed.post(mine.id) != nil)
    await source.setPosts([jaysRun, FeedPost(checkIn: mine, reactions: reactions([(jay, "💪", 450)]))])
    await feed.load()
    #expect(feed.post(mine.id)?.reactions.count(of: emoji("💪")) == 1)
    #expect(feed.sections.flatMap(\.posts).count == 2)
}

@MainActor @Test func teammatesNewReactionsOnMyPostsArriveNewestFirst() async {
    let mine = FeedPost(
        checkIn: checkIn(3, by: coco, on: "2026-10-22", at: 200),
        reactions: reactions([(mia, "😂", 300), (jay, "💪", 400)]))
    let older = FeedPost(
        checkIn: checkIn(4, by: coco, on: "2026-10-21", at: 100), reactions: reactions([(doudou, "❤️", 350)]))
    let feed = store(FakeSource([mine, older, jaysRun]))
    await feed.load()
    #expect(
        feed.arrivals(since: at(250)) == [
            Arrival(post: mine.id, member: jay, emoji: emoji("💪"), moment: at(400)),
            Arrival(post: older.id, member: doudou, emoji: emoji("❤️"), moment: at(350)),
        ])
    #expect(feed.arrivals(since: at(400)) == [])
}
