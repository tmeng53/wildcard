import Contracts
import Foundation
import Observation

/// The coach on 动态, as the server tells it. The app passes the API adapter (`Backend`), or the
/// sample squad's coach.
public protocol CoachSource: Sendable {
    /// The squad's newest 战术板 line and the coach's replies to `checkIns`, up to
    /// `FeedCoach.askLimit` of them.
    func activity(in squad: SquadID, about checkIns: [CheckInID]) async throws(FeedError) -> CoachActivity
}

/// What the squad's coach said on 动态: its 战术板 line, at the top of today while its day lasts,
/// and its replies, a line among a post's comments and an emoji first among its reactions, each
/// with the 教练 tag. Replies stay after the coach is fired, as the server keeps them; offline,
/// what was read stays.
@MainActor @Observable
public final class FeedCoach {
    /// The newest line the server sent, whatever its day.
    public private(set) var note: CoachNote?
    private var replies: [CheckInID: CoachReply] = [:]
    /// The posts already asked about, so the week before asks only for its own.
    private var asked: Set<CheckInID> = []

    /// The most posts one read asks about.
    public static let askLimit = 100

    private let source: any CoachSource
    private let squad: SquadID
    private let now: @Sendable () -> Date

    public init(source: any CoachSource, squad: SquadID, now: @escaping @Sendable () -> Date) {
        self.source = source
        self.squad = squad
        self.now = now
    }

    /// The 战术板 line while it is still its day (New York's, as every coach's).
    public var todaysNote: CoachNote? {
        guard let note, note.isCurrent(at: now()) else { return nil }
        return note
    }

    /// The coach's reply to a post, if it said or left anything.
    public func reply(to post: CheckInID) -> CoachReply? { replies[post] }

    /// Reads the line again and the replies to `posts`, newest first: the first `askLimit`.
    public func load(about posts: [CheckInID]) async {
        let asking = Array(posts.prefix(Self.askLimit))
        guard let activity = try? await source.activity(in: squad, about: asking) else { return }
        note = activity.note
        for reply in activity.replies where asking.contains(reply.checkIn) {
            replies[reply.checkIn] = reply
        }
        asked.formUnion(asking)
    }

    /// Reads the replies to those of `posts` not asked about yet: the week before, once shown.
    public func loadNew(_ posts: [CheckInID]) async {
        let new = posts.filter { !asked.contains($0) }
        guard !new.isEmpty else { return }
        await load(about: new)
    }
}
