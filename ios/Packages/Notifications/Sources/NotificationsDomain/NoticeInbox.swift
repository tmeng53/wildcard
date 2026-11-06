import Contracts
import Foundation
import Observation

/// The server, as 通知 needs it. The app passes the API adapter (`Backend`), or an in-memory
/// member for previews and UI tests.
public protocol NoticeSource: Sendable {
    /// A page of the member's notices, newest first: the newest page, or the one older than
    /// `before`.
    func notices(before: NoticeID?) async throws(NotificationsError) -> NoticePage
    /// Everything up to `through` is read. Safe to repeat; never goes back.
    func markSeen(through: NoticeID) async throws(NotificationsError)
    /// Hears notices as they are told, telling `heard` each, until the server ends the stream
    /// (it returns) or it can't be heard (it throws). Nothing told while it wasn't heard is
    /// replayed: each time it starts, `heard` gets `.ready`, and the newest page is read again.
    func listen(_ heard: @escaping @Sendable (LiveNotice) async -> Void) async throws(NotificationsError)
}

/// 通知's groups, in the order the page shows them.
public enum NoticeHeading: Hashable, Sendable, CaseIterable {
    /// 今天.
    case today
    /// 本周: since Monday, before today.
    case thisWeek
    /// 更早.
    case earlier
}

/// One group of 通知, newest first.
public struct NoticeSection: Hashable, Sendable, Identifiable {
    public let heading: NoticeHeading
    public let notices: [Notice]

    public var id: NoticeHeading { heading }

    /// `notices`, newest first, under 今天, 本周 and 更早 on the member's calendar at `now`, a
    /// week starting on Monday. A group with nothing in it is left out. Pieces that came to one
    /// store together, told within `together` of each other, are one row: the newest, which
    /// opens all their boxes (Tracy, 2026-11-04).
    public static func sections(_ notices: [Notice], now: Date, calendar: Calendar) -> [NoticeSection] {
        let notices = Self.joiningPieces(notices.sorted { $0.id > $1.id })
        var calendar = calendar
        calendar.firstWeekday = 2
        let today = calendar.startOfDay(for: now)
        let monday = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? today
        let grouped = Dictionary(grouping: notices) { notice -> NoticeHeading in
            if notice.toldAt >= today { .today } else if notice.toldAt >= monday { .thisWeek } else { .earlier }
        }
        return NoticeHeading.allCases.compactMap { heading in
            grouped[heading].map { NoticeSection(heading: heading, notices: $0.sorted { $0.id > $1.id }) }
        }
    }

    /// How close in time pieces' notices are to count as one arrival.
    static let together: TimeInterval = 60

    /// `newestFirst` without the pieces' notices that a newer one for the same store stands for.
    private static func joiningPieces(_ newestFirst: [Notice]) -> [Notice] {
        var kept: [Notice] = []
        for notice in newestFirst {
            if let store = pieceStore(notice), let newer = kept.last, pieceStore(newer) == store,
                newer.toldAt.timeIntervalSince(notice.toldAt) <= together
            {
                continue
            }
            kept.append(notice)
        }
        return kept
    }

    /// The store a piece's notice is about: the art names each piece `<store>-<piece>`.
    private static func pieceStore(_ notice: Notice) -> Substring? {
        guard case .unlocked(.piece, let item) = notice.subject else { return nil }
        return item.split(separator: "-").first
    }
}

/// 通知's data, behind the bell on 动态: the member's notices a page at a time, newest first, and
/// whether any is newer than what they have seen (the bell's dot). Opening the page marks every
/// one read; the ones that were new stay bold while it is open.
@MainActor @Observable
public final class NoticeInbox {
    /// Where loading stands.
    public enum Phase: Equatable, Sendable {
        /// Nothing loaded yet.
        case loading
        /// The notices are the server's, as of the last load.
        case current
        /// The server couldn't be reached on the last load.
        case offline
        /// The member is signed out.
        case signedOut
    }

    public private(set) var phase = Phase.loading
    public private(set) var notices: [Notice] = []
    /// Whether scrolling further can still find notices.
    public var hasMore: Bool { next != nil }
    /// Where the next page starts, nil at the end: changes each time a page is read, even one
    /// with nothing this build can show, so the end of the list knows to read on.
    public var nextPage: NoticeID? { next }
    /// Whether the last try at the next page didn't reach the server.
    public private(set) var moreFailed = false
    /// The bell's dot: a notice newer than the newest the member has seen.
    public var hasUnread: Bool {
        guard let newest = notices.first?.id else { return false }
        return seenThrough.map { newest > $0 } ?? true
    }

    /// The newest notice the member has seen, as the server last said or as this page marked.
    private var seenThrough: NoticeID?
    /// What had been seen when the page last opened: newer ones show as new until it opens again.
    private var seenWhenOpened: NoticeID?
    /// Whether 通知 is on screen.
    private var isOpen = false
    /// Whether the stream being heard got as far as `.ready`.
    private var heardReady = false
    private var next: NoticeID?
    /// Bumped by every fresh load, so an older page that comes back after it is dropped.
    private var generation = 0
    /// How many times the server said the member's 商店街 may have changed while the app was in
    /// front, or a stream heard again may have missed it: the app reads the shelf again on each.
    public private(set) var shelfChanges = 0
    /// Whether a stream was ready since `follow` started.
    private var listened = false
    private var loadingMore: Int?
    private let source: any NoticeSource

    /// The most pages one load or one scroll reads in a row while none of them has anything this
    /// build can show, before waiting for the member to scroll again.
    static let pagesAtOnce = 6

    public init(source: any NoticeSource) {
        self.source = source
    }

    /// The broadcasts (群发通知) on the loaded page that the member hasn't seen in 通知, the
    /// earliest told first: for the home's banner, which tells each once.
    public var unseenBroadcasts: [Broadcast] {
        notices.reversed().compactMap { notice in
            guard seenThrough.map({ notice.id > $0 }) ?? true, case .broadcast(let broadcast) = notice.subject else {
                return nil
            }
            return broadcast
        }
    }

    /// Whether `notice` is new to the member on the page as it is open now.
    public func isUnread(_ notice: Notice) -> Bool {
        seenWhenOpened.map { notice.id > $0 } ?? true
    }

    /// Loads the newest page, in place of what was loaded: for the bell's dot, and when the page
    /// opens or is pulled.
    public func load() async {
        generation += 1
        let mine = generation
        // With nothing to show yet, the page says it is loading, as on a retry after a failed one.
        if notices.isEmpty { phase = .loading }
        do {
            var page = try await source.notices(before: nil)
            var found = page.notices
            var read = 1
            // A page of kinds this build can't show still goes on past them.
            while found.isEmpty, let before = page.next, read < Self.pagesAtOnce {
                page = try await source.notices(before: before)
                found = page.notices
                read += 1
            }
            guard mine == generation else { return }
            // A notice heard live while the page was on its way is newer than all of it: kept.
            let live = notices.filter { notice in found.first.map { notice.id > $0.id } ?? false }
            notices = live + found
            next = page.next
            seenThrough = page.seenThrough
            moreFailed = false
            phase = .current
        } catch {
            // A read cut short (the page closed, the app went to the background) didn't fail.
            guard mine == generation, !Task.isCancelled else { return }
            phase = error == .signedOut ? .signedOut : (phase == .current ? .current : .offline)
        }
    }

    /// The page opened: loads the newest notices, keeps which were new for the bold rows, and
    /// marks everything up to the newest read, which takes the bell's dot away.
    public func open() async {
        isOpen = true
        await load()
        seenWhenOpened = seenThrough
        await markNewestSeen()
    }

    /// The page closed: what is told from now on lights the bell's dot again.
    public func close() {
        isOpen = false
    }

    /// Keeps the bell current while the app is open: listens for notices as they are told and,
    /// each time the stream ends or can't be heard, waits `pause` and listens again, until the
    /// task is cancelled (the app went to the background) or the session is over. A stream the
    /// server ended after it was ready waits `firstWait`, the server's `retry`; each try in a row
    /// that never got that far waits twice as long as the last, up to `longestWait`.
    public func follow(pause: @escaping @Sendable (Duration) async -> Void) async {
        var misses = 0
        // On the way back to the front the app reads 商店街 itself.
        listened = false
        while !Task.isCancelled {
            heardReady = false
            do {
                try await source.listen { [weak self] heard in await self?.hear(heard) }
            } catch .signedOut {
                return
            } catch {}
            guard !Task.isCancelled else { return }
            misses = heardReady ? 0 : misses + 1
            await pause(min(Self.firstWait * (1 << min(misses, 5)), Self.longestWait))
        }
    }

    /// The wait before listening again after the server ended a stream: its `retry`.
    public static let firstWait = Duration.seconds(3)
    /// The longest wait between tries while the stream can't be heard.
    public static let longestWait = Duration.seconds(60)

    func hear(_ heard: LiveNotice) async {
        switch heard {
        case .shelfChanged:
            shelfChanges += 1
        case .ready:
            // A stream heard again after one ended may have missed a change to 商店街 meanwhile.
            if listened { shelfChanges += 1 }
            (heardReady, listened) = (true, true)
            // Whatever was told while nobody listened is on the newest page.
            if isOpen { await refresh() } else { await load() }
        case .told(let notice):
            guard let notice, !notices.contains(where: { $0.id == notice.id }) else { return }
            notices.insert(notice, at: notices.firstIndex { $0.id < notice.id } ?? notices.endIndex)
            // On the open page it shows bold, and is read.
            if isOpen { await markNewestSeen() }
        }
    }

    /// The open page pulled: loads the newest notices and marks them read, keeping the rows that
    /// were new when it opened bold.
    public func refresh() async {
        await load()
        await markNewestSeen()
    }

    private func markNewestSeen() async {
        guard let newest = notices.first?.id, hasUnread else { return }
        seenThrough = newest
        try? await source.markSeen(through: newest)
    }

    /// Loads the next, older page, as the member scrolls to the end or tries again after a
    /// failed one. Goes on past pages this build can't show any of. Safe to call while one is
    /// loading.
    public func loadMore() async {
        let mine = generation
        guard next != nil, loadingMore != mine else { return }
        loadingMore = mine
        defer { if loadingMore == mine { loadingMore = nil } }
        moreFailed = false
        do {
            var found: [Notice] = []
            var read = 0
            while found.isEmpty, let before = next, read < Self.pagesAtOnce {
                let page = try await source.notices(before: before)
                guard mine == generation else { return }
                found = page.notices
                next = page.next
                read += 1
            }
            let shown = Set(notices.map(\.id))
            notices += found.filter { !shown.contains($0.id) }
        } catch {
            // Cut short (the list changed under it, the page closed), it didn't fail.
            guard mine == generation, !Task.isCancelled else { return }
            moreFailed = true
        }
    }
}
