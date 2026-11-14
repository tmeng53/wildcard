import Contracts
import Foundation
import Testing

@testable import NotificationsDomain

/// A member's notices on the server, a page of `size` at a time, newest first.
actor FakeNotices: NoticeSource {
    var all: [Notice]
    var seen: NoticeID?
    var size: Int
    var unreachable = false
    private(set) var marked: [NoticeID] = []
    private(set) var reads = 0
    /// Ids the server keeps but this build can't read: they take room on a page and never show.
    var unknown: Set<NoticeID> = []

    init(_ all: [Notice], seen: NoticeID? = nil, size: Int = 30) {
        (self.all, self.seen, self.size) = (all, seen, size)
    }

    func notices(before: NoticeID?) async throws(NotificationsError) -> NoticePage {
        reads += 1
        if let duringRead {
            self.duringRead = nil
            await duringRead()
        }
        if unreachable { throw .unavailable }
        let older = all.filter { notice in before.map { notice.id < $0 } ?? true }.sorted { $0.id > $1.id }
        let page = Array(older.prefix(size))
        let next = older.count > size ? page.last?.id : nil
        return NoticePage(notices: page.filter { !unknown.contains($0.id) }, seenThrough: seen, next: next)
    }

    func markSeen(through: NoticeID) async throws(NotificationsError) {
        // As URLSession does, a request from a cancelled task is cancelled and never arrives.
        if Task.isCancelled || refusesMarks { throw .unavailable }
        marked.append(through)
        seen = max(seen ?? through, through)
    }

    /// What each `listen` hears in turn, before the server ends that stream. Once these run out,
    /// it listens quietly until cancelled.
    var streams: [[LiveNotice]] = []
    /// What each `listen` throws in turn before it can be heard, ahead of `streams`.
    var refusals: [NotificationsError] = []

    func listen(_ heard: @escaping @Sendable (LiveNotice) async -> Void) async throws(NotificationsError) {
        if !refusals.isEmpty { throw refusals.removeFirst() }
        guard !streams.isEmpty else {
            let (quiet, open) = AsyncStream.makeStream(of: Never.self)
            for await _ in quiet {}
            open.finish()
            return
        }
        for event in streams.removeFirst() { await heard(event) }
    }

    func set(unreachable: Bool) { self.unreachable = unreachable }
    /// The mark request fails (the network dropped) while reads still work.
    var refusesMarks = false
    func set(refusesMarks: Bool) { self.refusesMarks = refusesMarks }
    func set(streams: [[LiveNotice]]) { self.streams = streams }
    func set(refusals: [NotificationsError]) { self.refusals = refusals }
    func hide(_ ids: Set<NoticeID>) { unknown = ids }
    func add(_ notice: Notice) { all.append(notice) }
    /// Runs once while the next page is on its way, as the live stream may tell a notice then.
    var duringRead: (@Sendable () async -> Void)?
    func set(duringRead: @escaping @Sendable () async -> Void) { self.duringRead = duringRead }
}

@Test @MainActor func theBellShowsItsDotOnlyForANoticeNewerThanTheSeenOne() async {
    let inbox = NoticeInbox(source: FakeNotices([notice(1), notice(2)], seen: NoticeID(rawValue: 2)))
    await inbox.load()
    #expect(!inbox.hasUnread)

    let fresh = NoticeInbox(source: FakeNotices([notice(1), notice(2), notice(3)], seen: NoticeID(rawValue: 2)))
    await fresh.load()
    #expect(fresh.hasUnread)

    // Never opened 通知: everything is new.
    let never = NoticeInbox(source: FakeNotices([notice(1)]))
    await never.load()
    #expect(never.hasUnread)

    let none = NoticeInbox(source: FakeNotices([]))
    await none.load()
    #expect(!none.hasUnread)
    #expect(none.phase == .current)
}

@Test @MainActor func openingMarksEverythingReadButKeepsTheNewOnesBoldWhileOpen() async {
    let server = FakeNotices([notice(1), notice(2), notice(3)], seen: NoticeID(rawValue: 1))
    let inbox = NoticeInbox(source: server)
    await inbox.open()

    #expect(await server.marked == [NoticeID(rawValue: 3)])
    #expect(!inbox.hasUnread)
    #expect(inbox.notices.map { inbox.isUnread($0) } == [true, true, false])

    // Opened again with nothing new: nothing is bold, and nothing is sent.
    await inbox.open()
    #expect(await server.marked == [NoticeID(rawValue: 3)])
    #expect(inbox.notices.map { inbox.isUnread($0) } == [false, false, false])
}

@Test @MainActor func aTappedRowIsReadOnTheOpenPage() async {
    let server = FakeNotices([notice(1), notice(2), notice(3)], seen: NoticeID(rawValue: 1))
    let inbox = NoticeInbox(source: server)
    await inbox.open()

    // The row of 3 tapped, a post pushed over the page and popped: only 2 is still new.
    inbox.opened(inbox.notices.filter { $0.id == NoticeID(rawValue: 3) })
    #expect(inbox.notices.map { inbox.isUnread($0) } == [false, true, false])
    #expect(await server.marked == [NoticeID(rawValue: 3)])
}

@Test @MainActor func pullingTheOpenPageMarksNewOnesReadAndKeepsTheBold() async {
    let server = FakeNotices([notice(1), notice(2)], seen: NoticeID(rawValue: 1))
    let inbox = NoticeInbox(source: server)
    await inbox.open()
    await server.add(notice(3))

    await inbox.refresh()
    #expect(await server.marked == [NoticeID(rawValue: 2), NoticeID(rawValue: 3)])
    #expect(!inbox.hasUnread)
    // What was new when the page opened stays bold, and so does what came in while it was open.
    #expect(inbox.notices.map { inbox.isUnread($0) } == [true, true, false])
}

@Test @MainActor func pagesGoOnPastNoticesThisBuildCantShow() async {
    let server = FakeNotices((1...7).map { notice($0) }, size: 2)
    // The newest page holds only kinds this build can't read, and so does one further down.
    await server.hide([NoticeID(rawValue: 7), NoticeID(rawValue: 6), NoticeID(rawValue: 3), NoticeID(rawValue: 2)])
    let inbox = NoticeInbox(source: server)

    await inbox.load()
    #expect(inbox.notices.map(\.id.rawValue) == [5, 4])
    #expect(inbox.hasMore)

    await inbox.loadMore()
    #expect(inbox.notices.map(\.id.rawValue) == [5, 4, 1])
    #expect(!inbox.hasMore)
}

@Test @MainActor func aLongRunOfUnknownPagesStopsAtSixAndMovesTheNextPageOn() async {
    // 20 pages of one notice each; only the oldest is a kind this build can show.
    let server = FakeNotices((1...20).map { notice($0) }, size: 1)
    await server.hide(Set((2...20).map { NoticeID(rawValue: $0) }))
    let inbox = NoticeInbox(source: server)

    await inbox.load()
    #expect(inbox.notices.isEmpty)
    #expect(await server.reads == 6)
    #expect(inbox.nextPage == NoticeID(rawValue: 15))

    // Each scroll reads at most six more and moves the next page on, so the end of the list
    // reads on again even though nothing showed.
    await inbox.loadMore()
    #expect(await server.reads == 12)
    #expect(inbox.nextPage == NoticeID(rawValue: 9))
    await inbox.loadMore()
    await inbox.loadMore()
    #expect(inbox.notices.map(\.id.rawValue) == [1])
    #expect(!inbox.hasMore)
}

@Test @MainActor func aReadCutShortIsNotAFailure() async {
    let server = FakeNotices((1...3).map { notice($0) }, size: 2)
    let inbox = NoticeInbox(source: server)
    await server.set(unreachable: true)
    let cut = Task { await inbox.load() }
    cut.cancel()
    await cut.value
    #expect(inbox.phase == .loading)

    await server.set(unreachable: false)
    await inbox.load()
    await server.set(unreachable: true)
    let page = Task { await inbox.loadMore() }
    page.cancel()
    await page.value
    #expect(!inbox.moreFailed)
}

@Test @MainActor func offlineKeepsWhatWasLoadedAndAFailedPageCanBeTriedAgain() async {
    let server = FakeNotices((1...3).map { notice($0) }, size: 2)
    let inbox = NoticeInbox(source: server)
    await server.set(unreachable: true)
    await inbox.load()
    #expect(inbox.phase == .offline)

    await server.set(unreachable: false)
    await inbox.load()
    #expect(inbox.notices.map(\.id.rawValue) == [3, 2])

    await server.set(unreachable: true)
    await inbox.load()
    #expect(inbox.phase == .current)
    #expect(inbox.notices.map(\.id.rawValue) == [3, 2])
    await inbox.loadMore()
    #expect(inbox.moreFailed)

    await server.set(unreachable: false)
    await inbox.loadMore()
    #expect(!inbox.moreFailed)
    #expect(inbox.notices.map(\.id.rawValue) == [3, 2, 1])
}

@Test @MainActor func aNoticeToldLiveLightsTheBellAndAReconnectReadsTheNewestPageAgain() async {
    let server = FakeNotices([notice(1), notice(2)], seen: NoticeID(rawValue: 2))
    let told = Notice(
        id: NoticeID(rawValue: 3), toldAt: monday, squad: nil, subject: .unlocked(.prop, item: "racket"))
    await server.set(streams: [[.ready, .told(told), .told(told), .told(nil)]])
    let inbox = NoticeInbox(source: server)
    await inbox.load()
    #expect(!inbox.hasUnread)

    let (paused, pause) = AsyncStream.makeStream(of: Void.self)
    let following = Task { await inbox.follow(pause: { _ in pause.yield() }) }
    var pauses = paused.makeAsyncIterator()
    // The server ended the first stream; the inbox waits, then listens again.
    _ = await pauses.next()
    #expect(await server.reads == 2)
    // Told once, though it came twice; a kind this build can't show is left out.
    #expect(inbox.notices.map(\.id.rawValue) == [3, 2, 1])
    #expect(inbox.hasUnread)
    // Its banner drops in once; nothing more until another is told.
    #expect(inbox.takeToldLive().map(\.id.rawValue) == [3])
    #expect(inbox.takeToldLive().isEmpty)
    following.cancel()
    await following.value
}

@Test @MainActor func aShelfChangeOrAStreamHeardAgainSaysToReadTheShelfAgain() async {
    let server = FakeNotices([notice(1)])
    // The first stream's ready reads nothing more; its shelf change does, and so does the next
    // stream's ready, which may have missed one.
    await server.set(streams: [[.ready, .shelfChanged], [.ready]])
    let inbox = NoticeInbox(source: server)
    let (paused, pause) = AsyncStream.makeStream(of: Void.self)
    let following = Task { await inbox.follow(pause: { _ in pause.yield() }) }
    var pauses = paused.makeAsyncIterator()
    _ = await pauses.next()
    #expect(inbox.shelfChanges == 1)
    _ = await pauses.next()
    #expect(inbox.shelfChanges == 2)
    following.cancel()
    await following.value

    // Back in front, the app reads the shelf itself: the first ready says nothing.
    await server.set(streams: [[.ready]])
    let again = Task { await inbox.follow(pause: { _ in pause.yield() }) }
    _ = await pauses.next()
    #expect(inbox.shelfChanges == 2)
    again.cancel()
    await again.value
}

@Test @MainActor func aNoticeToldWhileTheBellIsOpenIsReadButShowsBold() async {
    let server = FakeNotices([notice(1)], seen: NoticeID(rawValue: 1))
    let told = Notice(
        id: NoticeID(rawValue: 2), toldAt: monday, squad: nil, subject: .unlocked(.prop, item: "racket"))
    await server.set(streams: [[.told(told)]])
    let inbox = NoticeInbox(source: server)
    await inbox.open()

    let (paused, pause) = AsyncStream.makeStream(of: Void.self)
    let following = Task { await inbox.follow(pause: { _ in pause.yield() }) }
    var pauses = paused.makeAsyncIterator()
    _ = await pauses.next()
    #expect(!inbox.hasUnread)
    #expect(await server.marked.last == NoticeID(rawValue: 2))
    #expect(inbox.isUnread(told))
    // 通知 shows it: no banner over it.
    #expect(inbox.takeToldLive().isEmpty)
    following.cancel()
    await following.value

    // Closed, a notice told lights the dot again.
    inbox.close()
    await server.set(streams: [[.told(notice(3))]])
    let again = Task { await inbox.follow(pause: { _ in pause.yield() }) }
    _ = await pauses.next()
    #expect(inbox.hasUnread)
    again.cancel()
    await again.value
}

@Test @MainActor func aStreamThatCantBeHeardIsTriedLessOftenUntilItIsReadyAgain() async {
    let server = FakeNotices([notice(1)])
    await server.set(refusals: [.unavailable, .unavailable, .unavailable, .unavailable, .unavailable, .unavailable])
    await server.set(streams: [[.ready]])
    let inbox = NoticeInbox(source: server)

    let (paused, pause) = AsyncStream.makeStream(of: Duration.self)
    let following = Task { await inbox.follow(pause: { pause.yield($0) }) }
    var pauses = paused.makeAsyncIterator()
    var waits: [Duration] = []
    for _ in 0..<7 { waits.append(await pauses.next() ?? .zero) }
    // Doubling up to a minute while it fails; the server's 3 seconds once a stream was ready.
    #expect(waits.map { $0.components.seconds } == [6, 12, 24, 48, 60, 60, 3])
    following.cancel()
    await following.value
}

@Test @MainActor func aSessionThatIsOverStopsFollowing() async {
    let server = FakeNotices([notice(1)])
    await server.set(refusals: [.signedOut])
    let inbox = NoticeInbox(source: server)
    // It returns by itself, without waiting to try again.
    await inbox.follow(pause: { _ in Issue.record("waited after the session was over") })
}

@Test @MainActor func aNoticeHeardLiveStaysWhenALoadCameBackWithoutIt() async {
    let server = FakeNotices([notice(1), notice(2)], seen: NoticeID(rawValue: 2))
    let told = Notice(
        id: NoticeID(rawValue: 3), toldAt: monday, squad: nil, subject: .unlocked(.prop, item: "racket"))
    await server.set(streams: [[.told(told)]])
    let inbox = NoticeInbox(source: server)
    let (paused, pause) = AsyncStream.makeStream(of: Void.self)
    let following = Task { await inbox.follow(pause: { _ in pause.yield() }) }
    var pauses = paused.makeAsyncIterator()
    _ = await pauses.next()
    following.cancel()
    await following.value

    // A page read before the server had it, coming back after it was heard.
    await inbox.load()

    #expect(inbox.notices.map(\.id.rawValue) == [3, 2, 1])
}

@Test @MainActor func theHomeTellsTheBroadcastsNotYetSeenIn通知TheEarliestFirst() async {
    let words = { (line: String) in CatalogNames(simplifiedChinese: line, english: line, traditionalChinese: line) }
    let broadcast = { (id: String) in
        Broadcast(
            id: id, title: words(id), body: nil,
            action: Broadcast.Action(label: words("去商店街看看"), destination: .stores), style: .banner, gifts: [])
    }
    let told = { (id: Int, name: String) in
        Notice(id: NoticeID(rawValue: id), toldAt: monday, squad: nil, subject: .broadcast(broadcast(name)))
    }
    let suggested = Notice(
        id: NoticeID(rawValue: 5), toldAt: monday, squad: nil,
        subject: .goalSuggestion(GoalSuggestion(weeks: 3, daysPerMember: 4)))
    let server = FakeNotices(
        [told(1, "seen-already"), notice(2), told(3, "soon"), told(4, "today"), suggested], seen: NoticeID(rawValue: 2))
    let inbox = NoticeInbox(source: server)

    await inbox.load()

    #expect(inbox.unseenBroadcasts.map(\.id) == ["soon", "today"])
    #expect(inbox.notices.dropFirst().first?.destination == .stores)
    // A higher squad goal for the captain drops in the same way, and opens 小队.
    #expect(inbox.unseenGoalSuggestions.map(\.id.rawValue) == [5])
    #expect(inbox.unseenGoalSuggestions.first?.destination == .squad)
    await inbox.open()
    #expect(inbox.unseenBroadcasts.isEmpty)
    #expect(inbox.unseenGoalSuggestions.isEmpty)
}

@Test @MainActor func aBroadcastOpenedFromItsBannerIsNoLongerNew() async {
    let words = { (line: String) in CatalogNames(simplifiedChinese: line, english: line, traditionalChinese: line) }
    let broadcast = { (id: String) in
        Broadcast(
            id: id, title: words(id), body: nil,
            action: Broadcast.Action(label: words("去商店街看看"), destination: .stores), style: .banner, gifts: [])
    }
    let told = { (id: Int, name: String) in
        Notice(id: NoticeID(rawValue: id), toldAt: monday, squad: nil, subject: .broadcast(broadcast(name)))
    }

    // Another notice still waits unread: the bell's dot stays and nothing is marked, but in 通知
    // only that one shows as new.
    let busy = FakeNotices([notice(1), notice(2), told(3, "winter")], seen: NoticeID(rawValue: 1))
    let waiting = NoticeInbox(source: busy)
    await waiting.load()
    await waiting.opened(broadcast("winter"))
    #expect(waiting.hasUnread)
    #expect(await busy.marked.isEmpty)
    await waiting.open()
    #expect(waiting.notices.map { waiting.isUnread($0) } == [false, true, false])

    // It was the only one: the server marks it read, so it stays read on the next launch.
    let quiet = FakeNotices([notice(1), told(2, "winter")], seen: NoticeID(rawValue: 1))
    let inbox = NoticeInbox(source: quiet)
    await inbox.load()
    #expect(inbox.hasUnread)
    await inbox.opened(broadcast("winter"))
    #expect(!inbox.hasUnread)
    #expect(await quiet.marked == [NoticeID(rawValue: 2)])
    await inbox.open()
    #expect(inbox.notices.map { inbox.isUnread($0) } == [false, false])
}
