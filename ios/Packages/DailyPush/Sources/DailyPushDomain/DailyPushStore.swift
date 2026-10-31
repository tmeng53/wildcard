import Contracts
import FeedDomain
import Foundation
import Observation

/// The push's view state: the squad day it carried, with the member's reactions applied at once
/// and sent behind, one call at a time per post with its latest wish last, as 动态's `FeedStore`
/// does, so the server ends with the member's last pick. A reaction that doesn't reach the server
/// is put back.
@MainActor @Observable
public final class DailyPushStore {
    public private(set) var push: DailyPush
    @ObservationIgnored private let sender: any ReactionSender
    @ObservationIgnored private let now: () -> Date
    /// Each post's reactions as the server last took them.
    @ObservationIgnored private var taken: [CheckInID: Responses<Emoji>]
    /// The member's reaction not yet taken by the server, latest wish per post.
    @ObservationIgnored private var wishes: [CheckInID: Wish] = [:]
    /// The latest send going out, for tests to wait on.
    @ObservationIgnored private(set) var sending: Task<Void, Never>?
    @ObservationIgnored private var sendingPosts: Set<CheckInID> = []

    public init(push: DailyPush, sender: any ReactionSender, now: @escaping () -> Date) {
        self.push = push
        self.sender = sender
        self.now = now
        taken = Dictionary(push.posts.map { ($0.id, $0.reactions) }, uniquingKeysWith: { first, _ in first })
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
        let wish = Wish(emoji: emoji == before.reactions.kind(of: push.viewer) ? nil : emoji, since: Timestamp(now()))
        push.posts[index].reactions = wish.applied(to: before.reactions, by: push.viewer)
        wishes[id] = wish
        if !sendingPosts.contains(id) {
            sending = Task { await send(id) }
        }
        return wish.emoji.map(MoveID.init)
    }

    /// Sends the post's wishes one at a time until none is left: a pick made while one is going
    /// out goes next, so the server never takes an older pick after a newer one.
    private func send(_ id: CheckInID) async {
        sendingPosts.insert(id)
        defer { sendingPosts.remove(id) }
        while let wish = wishes[id] {
            do throws(DailyPushError) {
                try await sender.setReaction(wish.emoji, on: id)
                taken[id] = taken[id].map { wish.applied(to: $0, by: push.viewer) }
                if wishes[id] == wish { wishes[id] = nil }
            } catch {
                // A newer pick still goes out; otherwise the post shows what the server has.
                guard wishes[id] == wish else { continue }
                wishes[id] = nil
                if let index = push.posts.firstIndex(where: { $0.id == id }), let reactions = taken[id] {
                    push.posts[index].reactions = reactions
                }
            }
        }
    }
}

/// The reaction the member wants on a post, or none.
private struct Wish: Hashable, Sendable {
    let emoji: Emoji?
    let since: Timestamp

    func applied(to reactions: Responses<Emoji>, by member: MemberID) -> Responses<Emoji> {
        reactions.setting(emoji, for: member, at: since)
    }
}
