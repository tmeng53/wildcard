import Contracts
import Foundation

/// Why the chat didn't load, or something didn't go out. Each case is something the caller can
/// act on; the screen turns them into friendly copy.
public enum ChatError: Error, Equatable, Sendable {
    /// The server couldn't be reached; trying again is safe.
    case notSent
    /// The member isn't signed in any more.
    case signedOut
    /// The member isn't in the squad any more.
    case notInSquad
    /// The message is gone: its writer deleted it.
    case messageGone
    /// The server said no for a reason this build doesn't know. Trying again won't help.
    case refused
}

/// The server, as the chat needs it. The app passes the API adapter (`Backend`), or an in-memory
/// squad for previews and UI tests. Every write is safe to repeat.
public protocol ChatSource: Sendable {
    /// The newest page, or the one before `before` (a `seq`).
    func page(in squad: SquadID, before: Int?) async throws(ChatError) -> ChatPage
    /// Sends the member's message under the id given, and answers it as the server keeps it.
    func send(_ draft: ChatDraft, id: ChatMessageID, in squad: SquadID) async throws(ChatError) -> ChatMessage
    /// Deletes the member's own message.
    func delete(_ id: ChatMessageID, in squad: SquadID) async throws(ChatError)
    /// Sets the member's one emoji on a message, or takes it back when nil.
    func react(_ emoji: Emoji?, on id: ChatMessageID, in squad: SquadID) async throws(ChatError)
    /// Reports a squadmate's message (举报) to the admins; its writer isn't told.
    func report(_ id: ChatMessageID, in squad: SquadID) async throws(ChatError)
    func setAlerts(_ alerts: ChatAlerts, in squad: SquadID) async throws(ChatError)
    /// The member has seen everything up to `seq`. Never goes back.
    func markRead(through seq: Int, in squad: SquadID) async throws(ChatError)
    func unread(in squad: SquadID) async throws(ChatError) -> ChatUnread
    /// The squad's members' characters, by member. A member who hasn't made one yet is missing.
    func characters(in squad: SquadID) async throws(ChatError) -> [MemberID: MemberCharacter]
    /// The squad's coach now, and every coach's name, for messages from one it fired.
    func coaches(of squad: SquadID) async throws(ChatError) -> ChatCoaches
    /// Hears the member's live chat events until the stream ends.
    func listen(_ heard: @escaping @Sendable (ChatLive) async -> Void) async throws(ChatError)
}

/// The coaches the chat names: the squad's now, which @毛头 and the picker offer, and every
/// coach's name, since a fired coach's messages stay with their 教练 tag.
public struct ChatCoaches: Hashable, Sendable {
    public let current: CoachSpeaker?
    public let names: [CoachID: String]

    public init(current: CoachSpeaker?, names: [CoachID: String]) {
        self.current = current
        self.names = names
    }

    public static let none = ChatCoaches(current: nil, names: [:])

    /// The name a coach's message shows.
    public func name(of coach: CoachID) -> String? {
        current?.id == coach ? current?.name : names[coach]
    }
}
