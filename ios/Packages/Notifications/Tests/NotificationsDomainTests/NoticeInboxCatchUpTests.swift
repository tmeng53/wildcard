import Contracts
import Foundation
import Testing

@testable import NotificationsDomain

// A push that arrives while the app is in front: the app tells it in its own banner, so the
// inbox reads what is newer (`catchUp()`), each notice told once with the live stream.

@Test @MainActor func aPushInFrontHearsWhatIsNewerThanTheNewestAlreadyHereTheEarliestFirst() async {
    let server = FakeNotices([notice(1), notice(2)], seen: NoticeID(rawValue: 2))
    let inbox = NoticeInbox(source: server)
    await inbox.load()
    await server.add(notice(3))
    await server.add(notice(4))
    await inbox.catchUp(at: monday)
    #expect(inbox.takeToldLive().map(\.id.rawValue) == [3, 4])
    // A second push finds nothing newer.
    await inbox.catchUp(at: monday)
    #expect(inbox.takeToldLive().isEmpty)
}

@Test @MainActor func aNoticeToldLiveWhileAPushReadsThePageIsToldOnce() async {
    let server = FakeNotices([notice(1)])
    let inbox = NoticeInbox(source: server)
    await inbox.load()
    await server.add(notice(2))
    // The stream tells 2, and its banner takes it, while the push's read is on its way.
    await server.set(duringRead: { @MainActor in
        await inbox.hear(.told(notice(2)))
        #expect(inbox.takeToldLive().map(\.id.rawValue) == [2])
    })
    await inbox.catchUp(at: monday)
    #expect(inbox.takeToldLive().isEmpty)
}

@Test @MainActor func aPushWithNothingHereBeforeHearsOnlyWhatWasJustTold() async {
    // Notice 1 was told a day ago, 2 a minute before the push arrives on Tuesday.
    let server = FakeNotices([notice(1), notice(2, hoursAfterMonday: 24 - 1.0 / 60)])
    let inbox = NoticeInbox(source: server)
    await inbox.catchUp(at: monday.addingTimeInterval(24 * 3600))
    #expect(inbox.takeToldLive().map(\.id.rawValue) == [2])
}

@Test @MainActor func aPushForTheFirstNoticeEverIsHeard() async {
    let server = FakeNotices([])
    let inbox = NoticeInbox(source: server)
    await inbox.load()
    await server.add(notice(1))
    await inbox.catchUp(at: monday)
    #expect(inbox.takeToldLive().map(\.id.rawValue) == [1])
}

@Test @MainActor func aPushWith通知OpenHearsNothing() async {
    let server = FakeNotices([notice(1)])
    let inbox = NoticeInbox(source: server)
    await inbox.open()
    await server.add(notice(2))
    await inbox.catchUp(at: monday)
    #expect(inbox.takeToldLive().isEmpty)
}
