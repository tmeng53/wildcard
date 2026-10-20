import Contracts
import Observation

/// The 动态 tab's data: the squad's posts as last loaded, with the member's own reactions and
/// replies shown the moment they tap and sent behind. It never reads the clock itself: the app
/// passes the member's today and the time.
///
/// Responses go out one post at a time, newest wish last: tapping 加油 then 笑死 quickly ends
/// on 笑死 on the server too. When one can't go out, the post goes back to what the server has
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

    /// The posts as the server last sent them, with the responses the server took since.
    private var loaded: [CheckInID: FeedPost] = [:]
    /// The member's responses not yet taken by the server, latest wish per post.
    private var wishes: [Wish.Key: Wish] = [:]
    private var sending: Set<Wish.Key> = []
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

    // MARK: - Loading

    /// Loads the latest week, in place of what was loaded for those days.
    public func load() async {
        let latest = FeedRange.latest(today: today())
        if await load(latest) {
            range = range.map { FeedRange(first: min($0.first, latest.first), last: latest.last) } ?? latest
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
            for post in posts { loaded[post.id] = post }
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

    // MARK: - Responding

    /// The member reacts to a teammate's post: shown at once, sent by `sendResponses()`. Returns
    /// the move the author's character plays, nil when the member took their emoji back.
    @discardableResult
    public func react(_ gesture: ReactionGesture, on id: CheckInID) throws(FeedError) -> MoveID? {
        guard let post = post(id) else { throw .postGone }
        let change = try post.reacting(gesture, by: viewer, at: now())
        if change.changed { wishes[.init(post: id, channel: .reaction)] = .reaction(change.now, since: now()) }
        return change.now.map(MoveID.init)
    }

    /// The member taps a reply on a teammate's 请假条: shown at once, sent by `sendResponses()`.
    /// Returns the move the author's character plays, nil when the member took their reply back.
    @discardableResult
    public func reply(_ kind: ReplyKind, on id: CheckInID) throws(FeedError) -> MoveID? {
        guard let post = post(id) else { throw .postGone }
        let change = try post.replying(kind, by: viewer, at: now())
        if change.changed { wishes[.init(post: id, channel: .reply)] = .reply(change.now, since: now()) }
        return change.now.map { _ in .wave }
    }

    /// Sends every response not yet sent, each post's latest wish last. Safe to call any time:
    /// a post already going out picks up a newer wish when its call returns.
    public func sendResponses() async {
        for key in wishes.keys.sorted(by: { $0.post.description < $1.post.description }) {
            await send(key)
        }
    }

    public func dismissFailure() { failure = nil }

    private func send(_ key: Wish.Key) async {
        guard !sending.contains(key) else { return }
        sending.insert(key)
        defer { sending.remove(key) }
        while let wish = wishes[key] {
            do {
                switch wish {
                case .reaction(let emoji, _): try await source.setReaction(emoji, on: key.post)
                case .reply(let kind, _): try await source.setReply(kind, on: key.post)
                }
                if let post = loaded[key.post] { loaded[key.post] = wish.applied(to: post, by: viewer) }
                if wishes[key] == wish { wishes[key] = nil }
            } catch {
                // What the server has stays; the post shows it again.
                wishes[key] = nil
                if error == .postGone { loaded[key.post] = nil }
                failure = error
            }
        }
    }

    private func showing(_ post: FeedPost) -> FeedPost {
        var shown = post
        for channel in Wish.Channel.allCases {
            if let wish = wishes[.init(post: post.id, channel: channel)] { shown = wish.applied(to: shown, by: viewer) }
        }
        return shown
    }
}

/// A response the member wants on a post: their reaction or reply, or none.
private enum Wish: Hashable, Sendable {
    enum Channel: CaseIterable { case reaction, reply }

    struct Key: Hashable {
        let post: CheckInID
        let channel: Channel
    }

    case reaction(Emoji?, since: Timestamp)
    case reply(ReplyKind?, since: Timestamp)

    func applied(to post: FeedPost, by member: MemberID) -> FeedPost {
        var post = post
        switch self {
        case .reaction(let kind, let moment): post.reactions = post.reactions.setting(kind, for: member, at: moment)
        case .reply(let kind, let moment): post.replies = post.replies.setting(kind, for: member, at: moment)
        }
        return post
    }
}
