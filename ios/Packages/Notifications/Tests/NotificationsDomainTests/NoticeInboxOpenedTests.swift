import Contracts
import Foundation
import Testing

@testable import NotificationsDomain

// A notice whose place the member opened somewhere else (its post, the coach page, a push) is
// read on every phone: the bell leaves it out, and 通知 shows it read.

private func comment(_ id: Int, on post: CheckInID) -> Notice {
    Notice(
        id: NoticeID(rawValue: id), toldAt: hour(Double(id)), squad: nil,
        subject: .comment(PushAlert(key: "push.comment"), checkIn: post))
}

/// `hours` hours into the test's day: notice N is told at hour N.
private func hour(_ hours: Double) -> Date { Date(timeIntervalSince1970: hours * 3600) }

private let post = CheckInID(UUID(uuidString: "00000000-0000-4000-8000-000000000001") ?? UUID())
private let otherPost = CheckInID(UUID(uuidString: "00000000-0000-4000-8000-000000000002") ?? UUID())

@Test @MainActor func openingAPostClearsTheDotForItsNoticesOnly() async {
    let server = FakeNotices([comment(1, on: post), comment(2, on: otherPost), comment(3, on: post)])
    let inbox = NoticeInbox(source: server)
    await inbox.load()
    #expect(inbox.hasUnread)

    await inbox.visited(.post(post), at: hour(9))
    #expect(await server.openMarks == [[NoticeID(rawValue: 1), NoticeID(rawValue: 3)]])
    // The comment on the other post still waits.
    #expect(inbox.hasUnread)
    #expect(inbox.notices.map { inbox.isUnread($0) } == [false, true, false])

    await inbox.visited(.post(otherPost), at: hour(9))
    #expect(!inbox.hasUnread)
    // Opened again: nothing new to send.
    await inbox.visited(.post(post), at: hour(9))
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
    await inbox.visited(.post(post), at: hour(9))
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
    let page = Task { await inbox.visited(.post(post), at: hour(9)) }
    page.cancel()
    await page.value
    #expect(await server.openMarks == [[NoticeID(rawValue: 1)]])
}

@Test @MainActor func aNoticeAlreadySeenIsNotSentWhenItsPostOpens() async {
    let server = FakeNotices([comment(1, on: post), comment(2, on: otherPost)], seen: NoticeID(rawValue: 2))
    let inbox = NoticeInbox(source: server)
    await inbox.load()
    await inbox.visited(.post(post), at: hour(9))
    #expect(await server.openMarks.isEmpty)
}

@Test @MainActor func aPostOpenedBeforeItsNoticeLoadedStillReadsIt() async {
    // A comment's push tapped at launch: its post opens before the first page is here.
    let server = FakeNotices([comment(1, on: post), comment(2, on: otherPost)])
    let inbox = NoticeInbox(source: server)
    await inbox.visited(.post(post), at: hour(2.5))
    #expect(await server.openMarks.isEmpty)

    await inbox.load()
    #expect(await server.openMarks == [[NoticeID(rawValue: 1)]])
    #expect(inbox.notices.map { inbox.isUnread($0) } == [true, false])

    // Only once: a comment on it that comes later is new.
    await server.add(comment(3, on: post))
    await inbox.load()
    #expect(inbox.notices.map { inbox.isUnread($0) } == [true, true, false])
}

@Test @MainActor func aTappedPushForANoticeNotYetHeardIsReadOnceThePageLoads() async {
    let server = FakeNotices([comment(1, on: post)])
    let inbox = NoticeInbox(source: server)
    await inbox.load()
    // The push for 2 was told while the app was away; its tap opens the post first.
    await server.add(comment(2, on: post))
    await inbox.visited(.post(post), at: hour(9))
    await inbox.load()
    #expect(await server.openMarks == [[NoticeID(rawValue: 1)], [NoticeID(rawValue: 2)]])
    #expect(!inbox.hasUnread)
}

@Test @MainActor func aCommentToldAfterThePostWasLeftIsNew() async {
    let server = FakeNotices([comment(1, on: post)])
    let inbox = NoticeInbox(source: server)
    await inbox.load()
    await inbox.visited(.post(post), at: hour(1.5))
    // Hours later a squadmate comments while the app is away; the reconnect reads it.
    await server.add(comment(3, on: post))
    await inbox.load()
    #expect(inbox.notices.map { inbox.isUnread($0) } == [true, false])
    #expect(inbox.hasUnread)
}

@Test @MainActor func aPushTappedJustAsItsNoticeWasToldStillReadsIt() async {
    // The phone's clock runs half a minute behind the server's.
    let server = FakeNotices([comment(2, on: post)])
    let inbox = NoticeInbox(source: server)
    await inbox.visited(.post(post), at: hour(2).addingTimeInterval(-30))
    await inbox.load()
    #expect(!inbox.hasUnread)
}
