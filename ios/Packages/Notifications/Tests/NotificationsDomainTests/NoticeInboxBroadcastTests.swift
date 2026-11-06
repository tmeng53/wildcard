import Contracts
import Foundation
import NotificationsDomain
import Testing

// The broadcasts (群发通知) 通知 hands the home's banner (`NoticeInbox.unseenBroadcasts`).

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
    let server = FakeNotices(
        [told(1, "seen-already"), notice(2), told(3, "soon"), told(4, "today")], seen: NoticeID(rawValue: 2))
    let inbox = NoticeInbox(source: server)

    await inbox.load()

    #expect(inbox.unseenBroadcasts.map(\.id) == ["soon", "today"])
    #expect(inbox.notices.first?.destination == .stores)
    await inbox.open()
    #expect(inbox.unseenBroadcasts.isEmpty)
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
