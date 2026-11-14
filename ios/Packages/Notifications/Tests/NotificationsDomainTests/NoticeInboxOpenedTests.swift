import Contracts
import Foundation
import Testing

@testable import NotificationsDomain

// A notice whose place the member opened somewhere else (its post, the coach page, a push) is
// read on every phone: the bell leaves it out, and 通知 shows it read.

private func comment(_ id: Int, on post: CheckInID) -> Notice {
    Notice(
        id: NoticeID(rawValue: id), toldAt: Date(timeIntervalSince1970: TimeInterval(id)), squad: nil,
        subject: .comment(PushAlert(key: "push.comment"), checkIn: post))
}

private let post = CheckInID(UUID(uuidString: "00000000-0000-4000-8000-000000000001") ?? UUID())
private let otherPost = CheckInID(UUID(uuidString: "00000000-0000-4000-8000-000000000002") ?? UUID())

@Test @MainActor func openingAPostClearsTheDotForItsNoticesOnly() async {
    let server = FakeNotices([comment(1, on: post), comment(2, on: otherPost), comment(3, on: post)])
    let inbox = NoticeInbox(source: server)
    await inbox.load()
    #expect(inbox.hasUnread)

    await inbox.visited(.post(post))
    #expect(await server.openMarks == [[NoticeID(rawValue: 1), NoticeID(rawValue: 3)]])
    // The comment on the other post still waits.
    #expect(inbox.hasUnread)
    #expect(inbox.notices.map { inbox.isUnread($0) } == [false, true, false])

    await inbox.visited(.post(otherPost))
    #expect(!inbox.hasUnread)
    // Opened again: nothing new to send.
    await inbox.visited(.post(post))
    #expect(await server.openMarks.count == 2)
}

@Test @MainActor func whatAnotherPhoneOpenedIsReadHere() async {
    let server = FakeNotices([comment(1, on: post), comment(2, on: otherPost)])
    await server.set(openedOnServer: [NoticeID(rawValue: 2)])
    let inbox = NoticeInbox(source: server)
    await inbox.load()
    #expect(inbox.hasUnread)
    #expect(inbox.notices.map { inbox.isUnread($0) } == [false, true])

    await server.set(openedOnServer: [NoticeID(rawValue: 1), NoticeID(rawValue: 2)])
    await inbox.load()
    #expect(!inbox.hasUnread)
}

@Test @MainActor func anOpenTheServerMissedIsSentAgainAndStaysRead() async {
    let server = FakeNotices([comment(1, on: post)])
    let inbox = NoticeInbox(source: server)
    await inbox.load()
    await server.set(refusesMarks: true)
    await inbox.visited(.post(post))
    #expect(!inbox.hasUnread)
    #expect(await server.openMarks.isEmpty)

    await inbox.load()
    #expect(!inbox.hasUnread)

    await server.set(refusesMarks: false)
    await inbox.load()
    #expect(await server.openMarks == [[NoticeID(rawValue: 1)]])
}

@Test @MainActor func aPostLeftAtOnceStillMarksItsNoticesRead() async {
    let server = FakeNotices([comment(1, on: post)])
    let inbox = NoticeInbox(source: server)
    await inbox.load()
    let page = Task { await inbox.visited(.post(post)) }
    page.cancel()
    await page.value
    #expect(await server.openMarks == [[NoticeID(rawValue: 1)]])
}

@Test @MainActor func aNoticeAlreadySeenIsNotSentWhenItsPostOpens() async {
    let server = FakeNotices([comment(1, on: post), comment(2, on: otherPost)], seen: NoticeID(rawValue: 2))
    let inbox = NoticeInbox(source: server)
    await inbox.load()
    await inbox.visited(.post(post))
    #expect(await server.openMarks.isEmpty)
}
