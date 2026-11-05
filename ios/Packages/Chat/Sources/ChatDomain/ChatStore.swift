import Contracts
import Foundation
import Observation

/// 群聊's data: the squad's messages oldest first, as last loaded and as heard live, with the
/// member's own shown the moment they send and sent behind. It never reads the clock or makes ids
/// itself: the app passes the time and new messages' ids.
///
/// A message that can't go out stays in the chat marked failed (「没发出去 · 点一下重发」);
/// sending it again reuses its id, so the server saves it once whatever happened before.
@MainActor @Observable
public final class ChatStore {
    /// Where loading stands.
    public enum Phase: Equatable, Sendable {
        /// Nothing loaded yet.
        case loading
        /// The messages are the server's, as of the last load or event.
        case current
        /// The server can't be reached: 「网络开小差了」.
        case offline
        /// The member isn't in this squad any more.
        case notInSquad
        /// The member is signed out.
        case signedOut
    }

    /// Whether a message reached the server.
    public enum Delivery: Equatable, Sendable {
        case sent
        case sending
        case failed
    }

    /// A message as the chat shows it.
    public struct Line: Identifiable, Equatable, Sendable {
        public let message: ChatMessage
        public let delivery: Delivery
        public var id: ChatMessageID { message.id }
    }

    public private(set) var phase = Phase.loading
    /// Oldest first: the server's, then the member's own not yet taken, in the order sent.
    public private(set) var lines: [Line] = []
    /// Whether scrolling further back can still find messages.
    public private(set) var hasEarlier = false
    public private(set) var isLoadingEarlier = false
    public private(set) var alerts = ChatAlerts.mentions
    /// The coach writing now, while its three dots show.
    public private(set) var coachTyping: CoachID?
    public private(set) var characters: [MemberID: MemberCharacter] = [:]
    public private(set) var coaches = ChatCoaches.none
    /// The latest thing that couldn't go out, until `dismissFailure()`.
    public private(set) var failure: ChatError?

    public let squad: SquadID
    public let viewer: MemberID

    private var loaded: [ChatMessageID: ChatMessage] = [:]
    /// Messages replied to that aren't loaded, so a reply can show what it replies to.
    private var quoted: [ChatMessageID: ChatMessage] = [:]
    /// The member's own not yet taken, in the order sent.
    private var pending: [(message: ChatMessage, draft: ChatDraft, failed: Bool)] = []
    private var readThrough = 0
    private var markingRead = false

    private let source: any ChatSource
    private let now: @Sendable () -> Date
    private let newID: @Sendable () -> ChatMessageID

    public init(
        source: any ChatSource, squad: SquadID, viewer: MemberID, now: @escaping @Sendable () -> Date,
        newID: @escaping @Sendable () -> ChatMessageID
    ) {
        (self.source, self.squad, self.viewer, self.now, self.newID) = (source, squad, viewer, now, newID)
    }

    // MARK: Reading

    /// Loads the newest page, the squad's characters and its coaches. Older messages already
    /// loaded stay.
    public func load() async {
        do throws(ChatError) {
            let page = try await source.page(in: squad, before: nil)
            characters = try await source.characters(in: squad)
            coaches = try await source.coaches(of: squad)
            take(page, isNewest: true)
            phase = .current
        } catch {
            fail(error)
        }
    }

    /// The page before the oldest loaded.
    public func loadEarlier() async {
        guard hasEarlier, !isLoadingEarlier, let oldest = loaded.values.map(\.seq).min() else { return }
        isLoadingEarlier = true
        defer { isLoadingEarlier = false }
        do throws(ChatError) {
            take(try await source.page(in: squad, before: oldest), isNewest: false)
        } catch {
            fail(error)
        }
    }

    /// Listens for the squad's live events until the stream ends or the task is cancelled. While
    /// it is down the chat is offline; the caller calls it again to reconnect.
    public func listen() async {
        do throws(ChatError) {
            try await source.listen { [weak self] event in await self?.heard(event) }
        } catch {
            if error == .notSent { phase = .offline } else { fail(error) }
        }
    }

    /// One live event.
    public func heard(_ event: ChatLive) async {
        switch event {
        case .ready:
            await load()
        case .message(let squad, let message, let quote):
            if squad == self.squad { show(message, quoting: quote) }
        case .deleted(let squad, let id):
            guard squad == self.squad else { return }
            loaded[id] = nil
            quoted[id] = nil
            rebuild()
        case .coachTyping(let squad, let coach, let typing):
            guard squad == self.squad else { return }
            if typing { coachTyping = coach } else if coachTyping == coach { coachTyping = nil }
        }
    }

    /// A message heard live: new, or with its reactions changed. The coach's ends its dots.
    private func show(_ message: ChatMessage, quoting quote: ChatMessage?) {
        if let quote { quoted[quote.id] = quote }
        loaded[message.id] = message
        pending.removeAll { $0.message.id == message.id }
        if case .coach(let coach) = message.author, coach == coachTyping { coachTyping = nil }
        rebuild()
    }

    /// A message by id, whether loaded or only quoted.
    public func message(_ id: ChatMessageID) -> ChatMessage? {
        loaded[id] ?? quoted[id] ?? pending.first { $0.message.id == id }?.message
    }

    /// The name a message's writer shows, when it has one.
    public func name(of author: ChatAuthor) -> String? {
        switch author {
        case .member(let member): characters[member]?.nickname.text
        case .coach(let coach): coaches.name(of: coach)
        }
    }

    /// The member's emoji on a message.
    public func myReaction(on id: ChatMessageID) -> Emoji? {
        message(id)?.reactions.first { $0.member == viewer }?.emoji
    }

    /// Whether the chat has nothing in it yet: the squad and the coach in a row, 「场边还很安静」.
    public var isEmpty: Bool { phase != .loading && lines.isEmpty }

    /// Tells the server the member has seen everything shown. Safe to call on every change.
    public func markRead() async {
        guard let newest = loaded.values.map(\.seq).max(), newest > readThrough, !markingRead else { return }
        markingRead = true
        defer { markingRead = false }
        do throws(ChatError) {
            try await source.markRead(through: newest, in: squad)
            readThrough = max(readThrough, newest)
        } catch {
            // Read again on the next change; nothing to tell.
        }
    }

    // MARK: Writing

    /// Sends a message: shown at once, then sent.
    public func send(_ draft: ChatDraft) async {
        let message = ChatMessage(
            id: newID(), seq: 0, author: .member(viewer), kind: .text, text: draft.text.text, replyTo: draft.replyTo,
            mentions: draft.mentions, mentionsCoach: draft.mentionsCoach, sentAt: now(), reactions: [])
        pending.append((message, draft, false))
        rebuild()
        await deliver(message.id)
    }

    /// Sends a failed message again, under the same id.
    public func retry(_ id: ChatMessageID) async {
        guard let index = pending.firstIndex(where: { $0.message.id == id }), pending[index].failed else { return }
        pending[index].failed = false
        rebuild()
        await deliver(id)
    }

    private func deliver(_ id: ChatMessageID) async {
        guard let draft = pending.first(where: { $0.message.id == id })?.draft else { return }
        do throws(ChatError) {
            let saved = try await source.send(draft, id: id, in: squad)
            pending.removeAll { $0.message.id == id }
            loaded[saved.id] = saved
            phase = .current
        } catch {
            if let index = pending.firstIndex(where: { $0.message.id == id }) { pending[index].failed = true }
            if error != .notSent { failure = error }
        }
        rebuild()
    }

    /// Deletes the member's own message; one that never went out just goes.
    public func delete(_ id: ChatMessageID) async {
        if pending.contains(where: { $0.message.id == id }) {
            pending.removeAll { $0.message.id == id }
            rebuild()
            return
        }
        guard let message = loaded[id], message.member == viewer else { return }
        loaded[id] = nil
        rebuild()
        do throws(ChatError) {
            try await source.delete(id, in: squad)
        } catch {
            if error == .messageGone { return }
            loaded[id] = message
            failure = error
            rebuild()
        }
    }

    /// Sets the member's one emoji on a message, or takes it back when nil (picking theirs again).
    public func react(_ emoji: Emoji?, on id: ChatMessageID) async {
        guard let before = loaded[id] else { return }
        loaded[id] = before.reacting(emoji, by: viewer)
        rebuild()
        do throws(ChatError) {
            try await source.react(emoji, on: id, in: squad)
        } catch {
            if error == .messageGone {
                loaded[id] = nil
            } else {
                loaded[id] = loaded[id].map { $0.reacting(before.reactions.first { $0.member == viewer }?.emoji, by: viewer) }
                failure = error
            }
            rebuild()
        }
    }

    /// Reports a squadmate's message. True once the server has it.
    public func report(_ id: ChatMessageID) async -> Bool {
        do throws(ChatError) {
            try await source.report(id, in: squad)
            return true
        } catch {
            failure = error
            return false
        }
    }

    /// Changes when the member is pushed this squad's messages.
    public func setAlerts(_ alerts: ChatAlerts) async {
        let before = self.alerts
        self.alerts = alerts
        do throws(ChatError) {
            try await source.setAlerts(alerts, in: squad)
        } catch {
            self.alerts = before
            failure = error
        }
    }

    public func dismissFailure() { failure = nil }

    /// What a long press on a message offers: 回复 and 复制 for all, 举报 on a squadmate's, 删除 on
    /// the member's own. A message still going out offers only 删除.
    public func actions(for id: ChatMessageID) -> [MessageAction] {
        guard let line = lines.first(where: { $0.id == id }) else { return [] }
        if line.delivery != .sent { return [.copy, .delete] }
        switch line.message.author {
        case .coach: return [.reply, .copy]
        case .member(let member) where member == viewer: return [.reply, .copy, .delete]
        case .member: return [.reply, .copy, .report]
        }
    }

    // MARK: Inside

    private func take(_ page: ChatPage, isNewest: Bool) {
        for message in page.messages { loaded[message.id] = message }
        for message in page.quoted { quoted[message.id] = message }
        if isNewest {
            // A message gone from the newest page's range was deleted while the chat was closed.
            if let oldest = page.messages.map(\.seq).min() {
                for (id, message) in loaded
                where message.seq >= oldest && !page.messages.contains(where: { $0.id == id }) {
                    loaded[id] = nil
                }
            } else {
                loaded = [:]
            }
            pending.removeAll { item in loaded[item.message.id] != nil }
            alerts = page.alerts
            readThrough = max(readThrough, page.readThrough)
            if loaded.count == page.messages.count { hasEarlier = page.more }
        } else {
            hasEarlier = page.more
        }
        rebuild()
    }

    private func rebuild() {
        let server = loaded.values.sorted { $0.seq < $1.seq }.map { Line(message: $0, delivery: .sent) }
        let mine = pending.map { Line(message: $0.message, delivery: $0.failed ? .failed : .sending) }
        lines = server + mine
    }

    private func fail(_ error: ChatError) {
        switch error {
        case .notSent: phase = .offline
        case .signedOut: phase = .signedOut
        case .notInSquad: phase = .notInSquad
        case .messageGone, .refused: failure = error
        }
    }
}

/// What the long-press menu offers for a message.
public enum MessageAction: Hashable, Sendable {
    case reply
    case copy
    case report
    case delete
}
