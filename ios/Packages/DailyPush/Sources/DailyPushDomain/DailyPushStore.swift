import Contracts
import FeedDomain
import Foundation
import Observation

/// The push's view state: the squad day it carried, with the member's reactions applied at once
/// and sent behind. A reaction that doesn't reach the server is put back.
@MainActor @Observable
public final class DailyPushStore {
    public private(set) var push: DailyPush
    @ObservationIgnored private let sender: any ReactionSender
    @ObservationIgnored private let now: () -> Date
    /// Bumps on every reaction, so a late failure only undoes the latest one on its post.
    @ObservationIgnored private var sent: [CheckInID: Int] = [:]
    /// The latest reaction going out, for tests to wait on.
    @ObservationIgnored private(set) var sending: Task<Void, Never>?

    public init(push: DailyPush, sender: any ReactionSender, now: @escaping () -> Date = { Date() }) {
        self.push = push
        self.sender = sender
        self.now = now
    }

    public func post(_ id: CheckInID) -> PushPost? { push.posts.first { $0.id == id } }

    /// The member's emoji on the post: nil before they react.
    public func mine(on id: CheckInID) -> Emoji? { post(id)?.reactions.kind(of: push.viewer) }

    /// The member picks an emoji on a teammate's post: the same one again takes it back. Shows at
    /// once and goes out behind. Returns the move the author's character plays, or nil when it
    /// was taken back.
    @discardableResult
    public func pick(_ emoji: Emoji, on id: CheckInID) throws(DailyPushError) -> MoveID? {
        guard let index = push.posts.firstIndex(where: { $0.id == id }) else { throw .unknownPost }
        let before = push.posts[index]
        guard before.author != push.viewer else { throw .ownPost }
        let had = before.reactions.kind(of: push.viewer)
        let now: Emoji? = emoji == had ? nil : emoji
        push.posts[index].reactions = before.reactions.setting(now, for: push.viewer, at: Timestamp(self.now()))
        let attempt = (sent[id] ?? 0) + 1
        sent[id] = attempt
        let sender = sender
        sending = Task {
            do throws(DailyPushError) {
                try await sender.setReaction(now, on: id)
            } catch {
                undo(id, to: before.reactions, attempt: attempt)
            }
        }
        return now.map(MoveID.init)
    }

    /// Puts a post's row back after its latest reaction failed.
    private func undo(_ id: CheckInID, to reactions: Responses<Emoji>, attempt: Int) {
        guard sent[id] == attempt, let index = push.posts.firstIndex(where: { $0.id == id }) else { return }
        push.posts[index].reactions = reactions
    }
}
