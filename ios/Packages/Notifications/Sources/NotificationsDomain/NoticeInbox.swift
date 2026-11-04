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
    /// week starting on Monday. A group with nothing in it is left out.
    public static func sections(_ notices: [Notice], now: Date, calendar: Calendar) -> [NoticeSection] {
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
    private var next: NoticeID?
    /// Bumped by every fresh load, so an older page that comes back after it is dropped.
    private var generation = 0
    private var loadingMore: Int?
    private let source: any NoticeSource

    /// The most pages one load or one scroll reads in a row while none of them has anything this
    /// build can show, before waiting for the member to scroll again.
    static let pagesAtOnce = 6

    public init(source: any NoticeSource) {
        self.source = source
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
            notices = found
            next = page.next
            seenThrough = page.seenThrough
            moreFailed = false
            phase = .current
        } catch {
            guard mine == generation else { return }
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
    /// task is cancelled (the app went to the background).
    public func follow(pause: @escaping @Sendable () async -> Void) async {
        while !Task.isCancelled {
            try? await source.listen { [weak self] heard in await self?.hear(heard) }
            guard !Task.isCancelled else { return }
            await pause()
        }
    }

    func hear(_ heard: LiveNotice) async {
        switch heard {
        case .ready:
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
            guard mine == generation else { return }
            moreFailed = true
        }
    }
}

/// Where a tapped notice goes.
public enum NoticeTarget: Hashable, Sendable {
    /// 动态: the 6pm push's squad news.
    case feed
    /// The squad's 战报 for the week starting `week`.
    case recap(squad: SquadID?, week: LocalDay)
    /// 今天, on the squad's new scene.
    case home
    /// The member's check-in the coach answered, on its own page.
    case post(CheckInID)
    /// The character editor, where the store or prop opened.
    case wardrobe(Unlock.Kind, item: String)
}

extension Notice {
    public var target: NoticeTarget {
        switch subject {
        case .dailyProgress: .feed
        case .weeklyAwards(_, let week): .recap(squad: squad, week: week)
        case .sceneMoved: .home
        case .coachReply(let checkIn, _, _, _, _): .post(checkIn)
        case .unlocked(let kind, let item): .wardrobe(kind, item: item)
        case .comment(_, let checkIn): .post(checkIn)
        }
    }
}
