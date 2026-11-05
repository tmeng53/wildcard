import Contracts
import Foundation

/// A squad's chat kept in memory, for previews, UI tests, the sample squad and tests. It keeps the
/// API's rules: one emoji per member a message, only the writer deletes, a retry under the same
/// id saves once. When the coach is @'d or replied to, it answers after `coachPause`.
public actor InMemoryChatSource: ChatSource {
    private let viewer: MemberID
    private let squad: SquadID
    private var messages: [ChatMessage]
    private let characters: [MemberID: MemberCharacter]
    private let coaches: ChatCoaches
    private var alerts = ChatAlerts.mentions
    private var readThrough = 0
    private var nextSeq: Int
    private var listeners: [@Sendable (ChatLive) async -> Void] = []
    private let now: @Sendable () -> Date
    private let coachAnswer: @Sendable (String) -> String
    private let coachPause: @Sendable () async -> Void
    /// While true every call fails as `.notSent`, as offline would.
    public private(set) var isOffline = false
    /// What was reported, in order.
    public private(set) var reported: [ChatMessageID] = []
    /// Every message `send` was given, retries included.
    public private(set) var sendCalls: [ChatMessageID] = []

    public init(
        viewer: MemberID, squad: SquadID, messages: [ChatMessage], characters: [MemberID: MemberCharacter],
        coaches: ChatCoaches, now: @escaping @Sendable () -> Date = { Date() },
        coachAnswer: @escaping @Sendable (String) -> String = { _ in "收到！" },
        coachPause: @escaping @Sendable () async -> Void = {}
    ) {
        (self.viewer, self.squad, self.messages, self.characters, self.coaches) =
            (viewer, squad, messages, characters, coaches)
        nextSeq = (messages.map(\.seq).max() ?? 0) + 1
        (self.now, self.coachAnswer, self.coachPause) = (now, coachAnswer, coachPause)
    }

    public func setOffline(_ offline: Bool) { isOffline = offline }

    public func page(in squad: SquadID, before: Int?) async throws(ChatError) -> ChatPage {
        try check(squad)
        let older = messages.filter { before == nil || $0.seq < before ?? 0 }.sorted { $0.seq > $1.seq }
        let page = Array(older.prefix(50))
        let ids = Set(page.map(\.id))
        let quoted = page.compactMap(\.replyTo).filter { !ids.contains($0) }
            .compactMap { id in messages.first { $0.id == id } }
        return ChatPage(
            messages: page, quoted: quoted, more: older.count > page.count, readThrough: readThrough, alerts: alerts)
    }

    public func send(_ draft: ChatDraft, id: ChatMessageID, in squad: SquadID) async throws(ChatError)
        -> ChatMessage
    {
        sendCalls.append(id)
        try check(squad)
        if let saved = messages.first(where: { $0.id == id }) { return saved }
        let message = ChatMessage(
            id: id, seq: take(), author: .member(viewer), kind: .text, text: draft.text.text,
            replyTo: draft.replyTo.flatMap { reply in messages.contains { $0.id == reply } ? reply : nil },
            mentions: draft.mentions, mentionsCoach: draft.mentionsCoach && coaches.current != nil, sentAt: now(),
            reactions: [])
        messages.append(message)
        if let coach = coaches.current, asksCoach(message) {
            Task { await answer(message, as: coach.id) }
        }
        return message
    }

    private func asksCoach(_ message: ChatMessage) -> Bool {
        if message.mentionsCoach { return true }
        guard let reply = message.replyTo, let original = messages.first(where: { $0.id == reply }) else {
            return false
        }
        if case .coach = original.author { return true }
        return false
    }

    private func answer(_ message: ChatMessage, as coach: CoachID) async {
        await tell(.coachTyping(squad, coach, typing: true))
        await coachPause()
        let answer = ChatMessage(
            id: ChatMessageID(UUID()), seq: take(), author: .coach(coach), kind: .text,
            text: coachAnswer(message.text), replyTo: message.id, mentions: message.member.map { [$0] } ?? [],
            mentionsCoach: false, sentAt: now(), reactions: [])
        messages.append(answer)
        await tell(.message(squad, answer, quoted: message))
    }

    public func delete(_ id: ChatMessageID, in squad: SquadID) async throws(ChatError) {
        try check(squad)
        guard let message = messages.first(where: { $0.id == id }) else { return }
        guard message.member == viewer else { throw .refused }
        messages.removeAll { $0.id == id }
    }

    public func react(_ emoji: Emoji?, on id: ChatMessageID, in squad: SquadID) async throws(ChatError) {
        try check(squad)
        guard let index = messages.firstIndex(where: { $0.id == id }) else { throw .messageGone }
        messages[index] = messages[index].reacting(emoji, by: viewer)
    }

    public func report(_ id: ChatMessageID, in squad: SquadID) async throws(ChatError) {
        try check(squad)
        guard let message = messages.first(where: { $0.id == id }) else { throw .messageGone }
        guard message.member != viewer else { throw .refused }
        if !reported.contains(id) { reported.append(id) }
    }

    public func setAlerts(_ alerts: ChatAlerts, in squad: SquadID) async throws(ChatError) {
        try check(squad)
        self.alerts = alerts
    }

    public func markRead(through seq: Int, in squad: SquadID) async throws(ChatError) {
        try check(squad)
        readThrough = max(readThrough, seq)
    }

    public func unread(in squad: SquadID) async throws(ChatError) -> ChatUnread {
        try check(squad)
        let unread = messages.filter { $0.seq > readThrough && $0.member != viewer }
        return ChatUnread(count: unread.count, mentions: unread.filter { $0.mentions.contains(viewer) }.count)
    }

    public func characters(in squad: SquadID) async throws(ChatError) -> [MemberID: MemberCharacter] {
        try check(squad)
        return characters
    }

    public func coaches(of squad: SquadID) async throws(ChatError) -> ChatCoaches {
        try check(squad)
        return coaches
    }

    public func listen(_ heard: @escaping @Sendable (ChatLive) async -> Void) async throws(ChatError) {
        guard !isOffline else { throw .notSent }
        listeners.append(heard)
        await heard(.ready)
    }

    /// A squadmate writes, as the server would tell it live.
    public func receive(_ message: ChatMessage) async {
        let numbered = ChatMessage(
            id: message.id, seq: take(), author: message.author, kind: message.kind, text: message.text,
            replyTo: message.replyTo, mentions: message.mentions, mentionsCoach: message.mentionsCoach,
            sentAt: message.sentAt, reactions: message.reactions)
        messages.append(numbered)
        await tell(.message(squad, numbered, quoted: numbered.replyTo.flatMap { id in messages.first { $0.id == id } }))
    }

    private func tell(_ event: ChatLive) async {
        for listener in listeners { await listener(event) }
    }

    private func take() -> Int {
        defer { nextSeq += 1 }
        return nextSeq
    }

    private func check(_ squad: SquadID) throws(ChatError) {
        if isOffline { throw .notSent }
        guard squad == self.squad else { throw .notInSquad }
    }
}
