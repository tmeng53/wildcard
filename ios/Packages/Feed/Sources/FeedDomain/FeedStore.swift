import Contracts
import Foundation
import Observation

/// The 动态 tab's data: the squad's posts as last loaded, with the member's own reactions and
/// comments shown the moment they tap and sent behind. One post's own page reads the same store,
/// or one that holds only that post (`init(source:post:...)`), for a page opened from elsewhere.
/// It never reads the clock or makes ids itself: the app passes the member's today, the time and
/// new comments' ids.
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
    /// Whether the week before the earliest loaded is being read.
    public private(set) var isLoadingEarlier = false
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
    /// The member's comments shown before the server took them, by post, oldest first.
    private var pendingComments: [CheckInID: [Comment]] = [:]
    /// The member's last comment on each post that couldn't go out: sending the same words to
    /// the same person again reuses its id, so if the server had saved it after all it saves once.
    private var unsentComments: [CheckInID: Comment] = [:]
    /// The member's comments hidden while their deletion goes out.
    private var deleting: Set<CommentID> = []
    /// The days loaded so far, from the earliest.
    private var range: FeedRange?
    /// Weeks in a row that came back empty while going further back.
    private var emptyWeeks = 0

    /// After this many empty weeks in a row going back, the feed stops looking further.
    static let emptyWeeksBeforeTheStart = 4

    /// What the store holds: a squad's feed, or one post.
    private enum Scope {
        case squad(SquadID)
        case post(CheckInID)
    }

    private let source: any FeedSource
    private let scope: Scope
    private let viewer: MemberID
    private let today: @Sendable () -> LocalDay
    private let now: @Sendable () -> Timestamp
    private let newCommentID: @Sendable () -> CommentID

    /// A squad's feed.
    public init(
        source: any FeedSource, squad: SquadID, viewer: MemberID, today: @escaping @Sendable () -> LocalDay,
        now: @escaping @Sendable () -> Timestamp, newCommentID: @escaping @Sendable () -> CommentID
    ) {
        self.source = source
        self.scope = .squad(squad)
        self.viewer = viewer
        self.today = today
        self.now = now
        self.newCommentID = newCommentID
    }

    /// One post, for its own page opened from outside the feed (the member's past posts).
    public init(
        source: any FeedSource, post: CheckInID, viewer: MemberID, today: @escaping @Sendable () -> LocalDay,
        now: @escaping @Sendable () -> Timestamp, newCommentID: @escaping @Sendable () -> CommentID
    ) {
        self.source = source
        self.scope = .post(post)
        self.viewer = viewer
        self.today = today
        self.now = now
        self.newCommentID = newCommentID
        hasEarlier = false
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
    /// empty only for a squad that never posted. A store of one post loads that post.
    public func load() async {
        let squad: SquadID
        switch scope {
        case .post(let id):
            await refresh(id)
            guard let first = loaded[id]?.checkIn.audience.squads.first else { return }
            squad = first
        case .squad(let id):
            squad = id
        }
        if let characters = try? await source.characters(in: squad) { self.characters = characters }
        guard case .squad = scope else { return }
        let latest = FeedRange.latest(today: today())
        if await load(latest) {
            range = range.map { FeedRange(first: min($0.first, latest.first), last: latest.last) } ?? latest
        }
        for _ in 0..<Self.emptyWeeksBeforeTheStart where loaded.isEmpty && hasEarlier {
            await loadEarlier()
        }
    }

    /// Loads a post for its own page: a store of one post loads it and who is who; a squad's
    /// feed loads that post again.
    public func loadPost(_ id: CheckInID) async {
        if case .post = scope { await load() } else { await refresh(id) }
    }

    /// Loads one post again, with its latest reactions and comments.
    public func refresh(_ id: CheckInID) async {
        do {
            loaded[id] = try await source.post(id)
            ownNotYetListed[id] = nil
            phase = .current
        } catch {
            switch error {
            case .signedOut: phase = .signedOut
            case .postGone:
                forget(id)
                // A page of one post that is gone shows that, rather than loading for ever.
                if phase == .loading { phase = .current }
            default: if phase == .loading { phase = .offline }
            }
        }
    }

    /// Loads the week before the earliest loaded, as the member scrolls to the end. A call while
    /// one is under way does nothing, so the week is read once and the loader stays until it is.
    public func loadEarlier() async {
        guard case .squad = scope, !isLoadingEarlier, hasEarlier, let earlier = range?.earlier else { return }
        isLoadingEarlier = true
        defer { isLoadingEarlier = false }
        let before = loaded.count
        guard await load(earlier) else { return }
        range = FeedRange(first: earlier.first, last: range?.last ?? earlier.last)
        emptyWeeks = loaded.count == before ? emptyWeeks + 1 : 0
        hasEarlier = emptyWeeks < Self.emptyWeeksBeforeTheStart
    }

    /// True when the server answered.
    private func load(_ days: FeedRange) async -> Bool {
        guard case .squad(let squad) = scope else { return false }
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

    // MARK: - Comments

    /// The member writes a comment under a post, replying to someone or not: shown at once and
    /// sent. False when it couldn't go out, so the member's words stay in the box to try again;
    /// `failure` says why.
    @discardableResult
    public func comment(_ text: CommentText, replyingTo member: MemberID?, on id: CheckInID) async -> Bool {
        guard loaded[id] != nil else {
            failure = .postGone
            return false
        }
        let comment =
            unsentComments[id].flatMap { $0.text == text && $0.replyTo == member ? $0 : nil }
            ?? Comment(id: newCommentID(), member: viewer, text: text, replyTo: member, commentedAt: now())
        unsentComments[id] = nil
        pendingComments[id, default: []].append(comment)
        defer { pendingComments[id]?.removeAll { $0.id == comment.id } }
        do {
            let saved = try await source.comment(text, id: comment.id, replyingTo: member, on: id)
            if var post = loaded[id], !post.comments.contains(where: { $0.id == saved.id }) {
                post.comments.append(saved)
                loaded[id] = post
            }
            return true
        } catch {
            // The member's own post the server hasn't saved yet takes comments once it has.
            let error = error == .postGone && ownNotYetListed[id] != nil ? FeedError.notSent : error
            if error == .postGone { forget(id) } else { unsentComments[id] = comment }
            failure = error
            return false
        }
    }

    /// The member deletes their own comment: gone at once, and back if the server says no.
    public func deleteComment(_ comment: CommentID, on id: CheckInID) async {
        // One still going out can't be deleted yet: the delete could reach the server first.
        guard !isSending(comment, on: id) else { return }
        deleting.insert(comment)
        defer { deleting.remove(comment) }
        do {
            try await source.deleteComment(comment, on: id)
            if var post = loaded[id] {
                post.comments.removeAll { $0.id == comment }
                loaded[id] = post
            }
        } catch {
            if error == .postGone { forget(id) }
            failure = error
        }
    }

    /// True while the member's comment is still going out.
    public func isSending(_ comment: CommentID, on id: CheckInID) -> Bool {
        pendingComments[id]?.contains { $0.id == comment } ?? false
    }

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
                if error == .postGone { forget(key) }
                failure = error
            }
        }
    }

    /// The server says the post is gone: it leaves, unless it is the member's own that the server
    /// hasn't saved yet.
    private func forget(_ id: CheckInID) {
        loaded[id] = ownNotYetListed[id]
    }

    private func showing(_ post: FeedPost) -> FeedPost {
        var post = wishes[post.id].map { $0.applied(to: post, by: viewer) } ?? post
        let pending = (pendingComments[post.id] ?? []).filter { mine in
            !deleting.contains(mine.id) && !post.comments.contains { $0.id == mine.id }
        }
        post.comments = post.comments.filter { !deleting.contains($0.id) } + pending
        return post
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
