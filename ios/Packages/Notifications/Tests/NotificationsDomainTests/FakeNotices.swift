import Contracts

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
        return NoticePage(
            notices: page.filter { !unknown.contains($0.id) }, seenThrough: seen, next: next,
            opened: openedOnServer.intersection(page.map(\.id)))
    }

    /// What the server says was opened elsewhere, and each mark that reached it, in order.
    var openedOnServer: Set<NoticeID> = []
    private(set) var openMarks: [[NoticeID]] = []

    func markOpened(_ notices: [NoticeID]) async throws(NotificationsError) {
        if Task.isCancelled || refusesMarks { throw .unavailable }
        openMarks.append(notices)
        openedOnServer.formUnion(notices)
    }

    func set(openedOnServer: Set<NoticeID>) { self.openedOnServer = openedOnServer }

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
