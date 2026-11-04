import Contracts
import Foundation
import NotificationsDomain
import Testing

/// A member's notices on the server, a page of `size` at a time, newest first.
private actor FakeNotices: NoticeSource {
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
        if unreachable { throw .unavailable }
        let older = all.filter { notice in before.map { notice.id < $0 } ?? true }.sorted { $0.id > $1.id }
        let page = Array(older.prefix(size))
        let next = older.count > size ? page.last?.id : nil
        return NoticePage(notices: page.filter { !unknown.contains($0.id) }, seenThrough: seen, next: next)
    }

    func markSeen(through: NoticeID) async throws(NotificationsError) {
        marked.append(through)
        seen = max(seen ?? through, through)
    }

    func set(unreachable: Bool) { self.unreachable = unreachable }
    func hide(_ ids: Set<NoticeID>) { unknown = ids }
    func add(_ notice: Notice) { all.append(notice) }
}

private let monday = Date(timeIntervalSince1970: 1_793_577_600)  // 2026-11-02 00:00 UTC, a Monday

private func notice(_ id: Int, hoursAfterMonday hours: Double = 0) -> Notice {
    Notice(
        id: NoticeID(rawValue: id), toldAt: monday.addingTimeInterval(hours * 3600), squad: nil,
        subject: .unlocked(.store, item: "deuce"))
}

private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    return calendar
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

@Test func noticesGroupIntoTodayThisWeekAndEarlierOnAWeekFromMonday() {
    // Wednesday 2026-11-04 at 10:00.
    let now = monday.addingTimeInterval((48 + 10) * 3600)
    let notices = [
        notice(1, hoursAfterMonday: -1),  // Sunday night: last week
        notice(2, hoursAfterMonday: 1),  // Monday
        notice(3, hoursAfterMonday: 47),  // Tuesday, 23:00
        notice(4, hoursAfterMonday: 49),  // Wednesday, 1:00
        notice(5, hoursAfterMonday: 57),  // Wednesday, 9:00
    ]
    let sections = NoticeSection.sections(notices.shuffled(), now: now, calendar: utc)
    #expect(sections.map(\.heading) == [.today, .thisWeek, .earlier])
    #expect(sections.map { $0.notices.map(\.id.rawValue) } == [[5, 4], [3, 2], [1]])

    // Nothing today: the group is left out.
    #expect(
        NoticeSection.sections([notice(1, hoursAfterMonday: -1)], now: now, calendar: utc).map(\.heading) == [.earlier])
}

@Test func aPushLineSplitsIntoATitleAndWhatFollows() {
    let poke = PushAlertWords(PushAlert(key: "push.dailyProgress.poke", args: ["3", "12", "小林"]))
    let parts = poke.parts("%3$@拍了拍你 · 本周小队已练 %1$@/%2$@ 次")
    // The week comes first, as the approved bell design shows it, whatever order the push says it in.
    #expect(parts.title == "本周小队已练 3/12 次")
    #expect(parts.detail == "小林拍了拍你")

    let received = PushAlertWords(key: "push.dailyProgress.received", args: ["3", "12", "2"])
        .parts("本周小队已练 %1$@/%2$@ 次 · 今天 %3$@ 位队友给你打了气")
    #expect(received.title == "本周小队已练 3/12 次")
    #expect(received.detail == "今天 2 位队友给你打了气")

    let plain = PushAlertWords(key: "push.dailyProgress", args: ["3", "12"]).parts("本周小队已练 %1$@/%2$@ 次")
    #expect(plain.title == "本周小队已练 3/12 次")
    #expect(plain.detail == nil)
}

@Test func aCommentOpensThePostAndReadsAsItsPushPutIt() throws {
    let checkIn = CheckInID(try #require(UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")))
    let alert = PushAlert(key: "push.comment", args: ["Coco", "这组深蹲太稳了"])
    let comment = Notice(
        id: NoticeID(rawValue: 1), toldAt: monday, squad: nil, subject: .comment(alert, checkIn: checkIn))
    #expect(comment.target == .post(checkIn))
    let parts = PushAlertWords(alert).parts("%1$@ 评论了你：%2$@")
    #expect(parts.title == "Coco 评论了你：这组深蹲太稳了")
    #expect(parts.detail == nil)
}
