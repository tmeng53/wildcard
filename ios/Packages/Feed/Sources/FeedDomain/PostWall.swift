import Contracts
import Foundation
import Observation

/// The kinds 历史动态 can narrow to, in the order its filter shows them.
public enum PostKind: String, CaseIterable, Hashable, Sendable {
    case trained
    case healthyMeal
    case cheatMeal
    case disclaimer

    public init(_ entry: CheckIn.Entry) {
        self =
            switch entry {
            case .trained: .trained
            case .healthyMeal: .healthyMeal
            case .cheatMeal: .cheatMeal
            case .disclaimer: .disclaimer
            }
    }
}

/// One page of the member's own posts, newest first.
public struct MyPostsPage: Hashable, Sendable {
    public let posts: [FeedPost]
    /// Where the next page starts, as the server gave it; nil on the page that reaches the
    /// member's first post.
    public let next: String?
    /// How many posts the member ever made and the reactions on them they can see; the server
    /// sends them with the first page only.
    public let counts: MyPostCounts?

    public init(posts: [FeedPost], next: String?, counts: MyPostCounts?) {
        self.posts = posts
        self.next = next
        self.counts = counts
    }
}

/// 发过 N 条 · 收到 M 个表情: everything the member posted, never narrowed to a kind.
public struct MyPostCounts: Hashable, Sendable {
    public let posts: Int
    public let reactions: Int

    public init(posts: Int, reactions: Int) {
        self.posts = posts
        self.reactions = reactions
    }
}

/// The server, as 历史动态 needs it. The app passes the API adapter (`Backend`), or an in-memory
/// member for previews and UI tests.
public protocol MyPostsSource: Sendable {
    /// A page of the member's own posts, of one kind when given, after `after` when given.
    func myPosts(kind: PostKind?, after: String?) async throws(FeedError) -> MyPostsPage
    /// A post's photo, as JPEG. Nil when it can't be had now; the tile shows its colour instead.
    func photo(_ ref: PhotoRef) async -> Data?
}

/// One month of the wall: its posts, newest first.
public struct WallMonth: Hashable, Sendable, Identifiable {
    public let year: Int
    public let month: Int
    public let posts: [FeedPost]

    public var id: Int { year * 100 + month }

    /// Posts grouped by the month of the day they count for, newest month first, keeping the
    /// posts' order.
    public static func months(_ posts: [FeedPost]) -> [WallMonth] {
        var months: [WallMonth] = []
        for post in posts {
            let (year, month) = (post.checkIn.day.year, post.checkIn.day.month)
            if let last = months.last, last.year == year, last.month == month {
                months[months.count - 1] = WallMonth(year: year, month: month, posts: last.posts + [post])
            } else {
                months.append(WallMonth(year: year, month: month, posts: [post]))
            }
        }
        return months
    }
}

/// 历史动态's data: the member's own posts as a wall, a month at a heading, loaded a page at a
/// time as they scroll, narrowed to one kind when they pick one.
@MainActor @Observable
public final class PostWallStore {
    /// Where loading stands.
    public enum Phase: Equatable, Sendable {
        /// Nothing loaded yet.
        case loading
        /// The posts are the server's, as of the last load.
        case current
        /// The server couldn't be reached on the last load.
        case offline
        /// The member is signed out.
        case signedOut
    }

    public private(set) var phase = Phase.loading
    /// The kind shown; nil for all of them.
    public private(set) var kind: PostKind?
    public private(set) var posts: [FeedPost] = []
    public private(set) var counts: MyPostCounts?
    /// Whether scrolling further can still find posts.
    public var hasMore: Bool { next != nil }

    private var next: String?
    /// Bumped by every fresh load, so a page that comes back after the member picked another
    /// kind is dropped.
    private var generation = 0
    private var loadingMore = false
    private let source: any MyPostsSource

    public init(source: any MyPostsSource) {
        self.source = source
    }

    public var months: [WallMonth] { WallMonth.months(posts) }

    /// A post's photo, as JPEG; nil when it can't be had now.
    public func photo(_ ref: PhotoRef) async -> Data? { await source.photo(ref) }

    /// Loads the newest page of the kind shown, in place of what was loaded.
    public func load() async {
        generation += 1
        let mine = generation
        do {
            let page = try await source.myPosts(kind: kind, after: nil)
            guard mine == generation else { return }
            posts = page.posts
            next = page.next
            if let counts = page.counts { self.counts = counts }
            phase = .current
        } catch {
            guard mine == generation else { return }
            phase = error == .signedOut ? .signedOut : (phase == .current ? .current : .offline)
        }
    }

    /// Shows only `kind`, or every kind for nil, from the newest.
    public func show(_ kind: PostKind?) async {
        guard kind != self.kind else { return }
        self.kind = kind
        posts = []
        next = nil
        phase = .loading
        await load()
    }

    /// Loads the next page, as the member scrolls to the end. Safe to call while one is loading.
    public func loadMore() async {
        guard let after = next, !loadingMore else { return }
        loadingMore = true
        defer { loadingMore = false }
        let mine = generation
        guard let page = try? await source.myPosts(kind: kind, after: after), mine == generation else { return }
        let seen = Set(posts.map(\.id))
        posts += page.posts.filter { !seen.contains($0.id) }
        next = page.next
    }
}
