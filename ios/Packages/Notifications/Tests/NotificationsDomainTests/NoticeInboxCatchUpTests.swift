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
    await inbox.catchUp()
    #expect(inbox.takeToldLive().map(\.id.rawValue) == [3, 4])
    // A second push finds nothing newer.
    await inbox.catchUp()
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
    await inbox.catchUp()
    #expect(inbox.takeToldLive().isEmpty)
}

@Test @MainActor func aPushBeforeAnythingLoadedOrWith通知OpenHearsNothing() async {
    let server = FakeNotices([notice(1)])
    let inbox = NoticeInbox(source: server)
    // Nothing was here to be newer than: every notice on the page would be heard at once.
    await inbox.catchUp()
    #expect(inbox.takeToldLive().isEmpty)
    await inbox.open()
    await server.add(notice(2))
    await inbox.catchUp()
    #expect(inbox.takeToldLive().isEmpty)
}
