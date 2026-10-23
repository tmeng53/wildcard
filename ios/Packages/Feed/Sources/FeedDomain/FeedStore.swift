import Contracts
import Foundation
import Observation

/// The 动态 tab's data: the squad's posts as last loaded, with the member's own reactions shown
/// the moment they tap and sent behind. It never reads the clock itself: the app
/// passes the member's today and the time.
///
/// Reactions go out one post at a time, newest wish last: tapping 💪 then 😂 quickly ends on 😂
/// on the server too. When one can't go out, the post goes back to what the server has
/// and `failure` says why.
@MainActor @Observable
public final class FeedStore {
    /// Where loading stands.
    public enum Phase: Equatable, Sendable {
        /// Nothing loaded yet.
        case loading
        /// The posts are the server's, as of the last load.
        case current
        /// The server couldn't be reached on the last load.
        case offline
        /// The member isn't in this squad any more.
        case notInSquad
        /// The member is signed out.
        case signedOut
    }

    public private(set) var phase = Phase.loading
    /// The latest response that couldn't go out, until `dismissFailure()`.
    public private(set) var failure: FeedError?
    /// Whether scrolling further back can still find posts.
    public private(set) var hasEarlier = true
    /// The squad's members' characters as last loaded: names and looks.
    public private(set) var characters: [MemberID: MemberCharacter] = [:]

    /// The posts as the server last sent them, with the responses the server took since.
    private var loaded: [CheckInID: FeedPost] = [:]
    /// The member's responses not yet taken by the server, latest wish per post.
    private var wishes: [CheckInID: Wish] = [:]
    private var sending: Set<CheckInID> = []
    /// The member's own posts shown before the server listed them (`show(_:)`), kept across
    /// loads until it does.
    private var ownNotYetListed: [CheckInID: FeedPost] = [:]
    /// The days loaded so far, from the earliest.
    private var range: FeedRange?
    /// Weeks in a row that came back empty while going further back.
    private var emptyWeeks = 0

    /// After this many empty weeks in a row going back, the feed stops looking further.
    static let emptyWeeksBeforeTheStart = 4

    private let source: any FeedSource
    private let squad: SquadID
    private let viewer: MemberID
    private let today: @Sendable () -> LocalDay
    private let now: @Sendable () -> Timestamp

    public init(
        source: any FeedSource, squad: SquadID, viewer: MemberID, today: @escaping @Sendable () -> LocalDay,
        now: @escaping @Sendable () -> Timestamp
    ) {
        self.source = source
        self.squad = squad
        self.viewer = viewer
        self.today = today
        self.now = now
    }

    // MARK: - Reading

    /// The posts by day, newest first, with the member's responses on their way already in.
    public var sections: [FeedSection] {
        FeedSection.sections(loaded.values.map(showing), today: today())
    }

    public func post(_ id: CheckInID) -> FeedPost? { loaded[id].map(showing) }

    /// A post's photo, as JPEG; nil when it can't be had now.
    public func photo(_ ref: PhotoRef) async -> Data? { await source.photo(ref) }

    // MARK: - Loading

    /// Loads the latest week, in place of what was loaded for those days, and who is who. A
    /// squad that was quiet all week goes back until it finds its last posts, so the feed is
    /// empty only for a squad that never posted.
    public func load() async {
        if let characters = try? await source.characters(in: squad) { self.characters = characters }
        let latest = FeedRange.latest(today: today())
        if await load(latest) {
            range = range.map { FeedRange(first: min($0.first, latest.first), last: latest.last) } ?? latest
        }
        for _ in 0..<Self.emptyWeeksBeforeTheStart where loaded.isEmpty && hasEarlier {
            await loadEarlier()
        }
    }

    /// Loads the week before the earliest loaded, as the member scrolls to the end.
    public func loadEarlier() async {
        guard hasEarlier, let earlier = range?.earlier else { return }
        let before = loaded.count
        guard await load(earlier) else { return }
        range = FeedRange(first: earlier.first, last: range?.last ?? earlier.last)
        emptyWeeks = loaded.count == before ? emptyWeeks + 1 : 0
        hasEarlier = emptyWeeks < Self.emptyWeeksBeforeTheStart
    }

    /// True when the server answered.
    private func load(_ days: FeedRange) async -> Bool {
        do {
            let posts = try await source.posts(in: squad, from: days.first, through: days.last)
            loaded = loaded.filter { !(days.first...days.last).contains($0.value.checkIn.day) }
            for post in posts {
                loaded[post.id] = post
                ownNotYetListed[post.id] = nil
            }
            for (id, post) in ownNotYetListed where loaded[id] == nil { loaded[id] = post }
            phase = .current
            return true
        } catch {
            switch error {
            case .signedOut: phase = .signedOut
            case .notInSquad: phase = .notInSquad
            default: if phase == .loading { phase = .offline }
            }
            return false
        }
    }

    /// Shows a post the member just made, which the last load may not have: it may still be
    /// waiting to go out. 动态 opens on it from the home.
    public func show(_ checkIn: CheckIn) {
        guard checkIn.member == viewer, loaded[checkIn.id] == nil else { return }
        let post = FeedPost(checkIn: checkIn)
        loaded[checkIn.id] = post
        ownNotYetListed[checkIn.id] = post
    }

    /// Teammates' reactions on the member's own posts left after `moment`, the newest on each
    /// post, newest first: what their character answers when 动态 opens.
    public func arrivals(since moment: Timestamp) -> [Arrival] {
        loaded.values
            .filter { $0.author == viewer }
            .compactMap { post in
                post.reactions.all.last { $0.member != viewer && $0.moment > moment }
                    .map { Arrival(post: post.id, member: $0.member, emoji: $0.kind, moment: $0.moment) }
            }
            .sorted { ($0.moment, $0.post.description) > ($1.moment, $1.post.description) }
    }

    // MARK: - Responding

    /// The member reacts to a teammate's post: shown at once, sent by `sendResponses()`. Returns
    /// the move the author's character plays, nil when the member took their emoji back.
    @discardableResult
    public func react(_ gesture: ReactionGesture, on id: CheckInID) throws(FeedError) -> MoveID? {
        guard let post = post(id) else { throw .postGone }
        let change = try post.reacting(gesture, by: viewer, at: now())
        if change.changed { wishes[id] = Wish(emoji: change.now, since: now()) }
        return change.now.map(MoveID.init)
    }

    /// Sends every response not yet sent, each post's latest wish last. Safe to call any time:
    /// a post already going out picks up a newer wish when its call returns.
    public func sendResponses() async {
        for key in wishes.keys.sorted(by: { $0.description < $1.description }) {
            await send(key)
        }
    }

    public func dismissFailure() { failure = nil }

    private func send(_ key: CheckInID) async {
        guard !sending.contains(key) else { return }
        sending.insert(key)
        defer { sending.remove(key) }
        while let wish = wishes[key] {
            do {
                try await source.setReaction(wish.emoji, on: key)
                if let post = loaded[key] { loaded[key] = wish.applied(to: post, by: viewer) }
                if wishes[key] == wish { wishes[key] = nil }
            } catch {
                // What the server has stays; the post shows it again.
                wishes[key] = nil
                if error == .postGone { loaded[key] = nil }
                failure = error
            }
        }
    }

    private func showing(_ post: FeedPost) -> FeedPost {
        wishes[post.id].map { $0.applied(to: post, by: viewer) } ?? post
    }
}

/// The reaction the member wants on a post, or none.
private struct Wish: Hashable, Sendable {
    let emoji: Emoji?
    let since: Timestamp

    func applied(to post: FeedPost, by member: MemberID) -> FeedPost {
        var post = post
        post.reactions = post.reactions.setting(emoji, for: member, at: since)
        return post
    }
}

/// A teammate's reaction on one of the member's own posts.
public struct Arrival: Hashable, Sendable {
    public let post: CheckInID
    public let member: MemberID
    public let emoji: Emoji
    public let moment: Timestamp
}
