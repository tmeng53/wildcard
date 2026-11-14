import Contracts
import Testing

@testable import NotificationsDomain

// How far the member has read reaches the server, however soon 通知 is left, and a phone that
// marked never shows the bell's dot again for what it marked.

@Test @MainActor func aPageLeftAtOnceStillMarksEverythingRead() async {
    let server = FakeNotices([notice(1), notice(2), notice(3)], seen: NoticeID(rawValue: 1))
    let inbox = NoticeInbox(source: server)
    await inbox.load()
    #expect(inbox.hasUnread)

    // 通知 opened and left (back, a row tapped, another tab) before its mark went out: SwiftUI
    // cancels the page's task, and the mark must reach the server all the same.
    let page = Task { await inbox.open() }
    page.cancel()
    await page.value
    #expect(await server.marked == [NoticeID(rawValue: 3)])

    // 动态 read again: the dot stays off.
    await inbox.load()
    #expect(!inbox.hasUnread)
}

@Test @MainActor func aMarkTheServerMissedIsSentAgainAndTheDotStaysOff() async {
    let server = FakeNotices([notice(1), notice(2)], seen: NoticeID(rawValue: 1))
    let inbox = NoticeInbox(source: server)
    await server.set(refusesMarks: true)
    await inbox.open()
    #expect(await server.marked.isEmpty)

    // The server still says 1 was the last seen: what this phone marked wins, so no dot.
    await inbox.load()
    #expect(!inbox.hasUnread)

    // Back online, the next load sends it.
    await server.set(refusesMarks: false)
    await inbox.load()
    #expect(await server.marked == [NoticeID(rawValue: 2)])
    #expect(await server.seen == NoticeID(rawValue: 2))
    #expect(!inbox.hasUnread)

    // Nothing left to send.
    await inbox.load()
    #expect(await server.marked == [NoticeID(rawValue: 2)])
}
