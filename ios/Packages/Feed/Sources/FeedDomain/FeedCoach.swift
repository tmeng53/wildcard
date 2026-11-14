import Contracts
import Foundation
import Observation

/// The coach on 动态, as the server tells it. The app passes the API adapter (`Backend`), or the
/// sample squad's coach.
public protocol CoachSource: Sendable {
    /// The squad's newest 战术板 line and the coach's replies to `checkIns`, up to
    /// `FeedCoach.askLimit` of them.
    func activity(in squad: SquadID, about checkIns: [CheckInID]) async throws(FeedError) -> CoachActivity
    /// The coach the squad has hired now, which members may @; nil while it has none.
    func hiredCoach(in squad: SquadID) async throws(FeedError) -> CoachSpeaker?
}

/// What the squad's coach said on 动态: its 战术板 line, at the top of today while its day lasts,
/// and its replies, a line among a post's comments and an emoji first among its reactions, each
/// with the 教练 tag. Replies stay after the coach is fired, as the server keeps them; offline,
/// what was read stays.
@MainActor @Observable
public final class FeedCoach {
    /// The newest line the server sent, whatever its day.
    public private(set) var note: CoachNote?
    /// The coach the squad has hired now, first in the @ list; nil while it has none (or before
    /// the first read).
    public private(set) var hired: CoachSpeaker?
    private var replies: [CheckInID: CoachReply] = [:]
    private var answers: [CheckInID: [CoachAnswer]] = [:]
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

    /// The 战术板 line while it is still its day, on the squad's clock (`CoachNote.timeZone`).
    public var todaysNote: CoachNote? {
        guard let note, note.isCurrent(at: now()) else { return nil }
        return note
    }

    /// The coach's reply to a post, if it said or left anything.
    public func reply(to post: CheckInID) -> CoachReply? { replies[post] }

    /// The coach's answers to members' replies to it under a post, oldest first.
    public func answers(on post: CheckInID) -> [CoachAnswer] { answers[post] ?? [] }

    /// A coach that spoke on 动态, by id: its name for 回复 毛头.
    public func speaker(_ coach: CoachID) -> CoachSpeaker? {
        let all =
            replies.values.map(\.coach) + answers.values.flatMap { $0.map(\.coach) } + [note?.coach].compactMap(\.self)
        return all.first { $0.id == coach }
    }

    /// Reads the line again, the squad's coach now and the replies to `posts`, newest first: the
    /// first `askLimit`.
    public func load(about posts: [CheckInID]) async {
        let asking = Array(posts.prefix(Self.askLimit))
        async let hiring = hiredNow()
        guard let activity = try? await source.activity(in: squad, about: asking) else { return }
        // Offline, the coach read before stays.
        if case .some(let read) = await hiring { hired = read }
        note = activity.note
        for reply in activity.replies where asking.contains(reply.checkIn) {
            replies[reply.checkIn] = reply
        }
        // Each post asked about has exactly the answers it was sent: none when they went.
        for post in asking {
            answers[post] = activity.answers.filter { $0.checkIn == post }
        }
        asked.formUnion(asking)
    }

    /// The squad's coach now, `.some(nil)` for none, or nil when it couldn't be read.
    private func hiredNow() async -> CoachSpeaker?? {
        do throws(FeedError) {
            return .some(try await source.hiredCoach(in: squad))
        } catch {
            return nil
        }
    }

    /// Reads the replies to those of `posts` not asked about yet: the week before, once shown.
    public func loadNew(_ posts: [CheckInID]) async {
        let new = posts.filter { !asked.contains($0) }
        guard !new.isEmpty else { return }
        await load(about: new)
    }
}
