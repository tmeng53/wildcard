import ChatDomain
import Contracts
import Foundation

/// 群聊 over the API: `ChatDomain`'s `ChatSource`.
public struct APIChatSource: ChatSource {
    private let api: WildcardAPI

    public init(api: WildcardAPI) {
        self.api = api
    }

    public func page(in squad: SquadID, before: Int?) async throws(ChatError) -> ChatPage {
        try await chat { () throws(APIError) in try await api.chatPage(in: squad, before: before) }
    }

    public func send(_ draft: ChatDraft, id: ChatMessageID, in squad: SquadID) async throws(ChatError) -> ChatMessage {
        try await chat { () throws(APIError) in try await api.send(draft, id: id, in: squad) }
    }

    public func delete(_ id: ChatMessageID, in squad: SquadID) async throws(ChatError) {
        try await chat { () throws(APIError) in try await api.deleteChatMessage(id, in: squad) }
    }

    public func react(_ emoji: Emoji?, on id: ChatMessageID, in squad: SquadID) async throws(ChatError) {
        try await chat { () throws(APIError) in try await api.react(emoji, on: id, in: squad) }
    }

    public func report(_ id: ChatMessageID, in squad: SquadID) async throws(ChatError) {
        try await chat { () throws(APIError) in try await api.report(id, in: squad) }
    }

    public func setAlerts(_ alerts: ChatAlerts, in squad: SquadID) async throws(ChatError) {
        try await chat { () throws(APIError) in try await api.setChatAlerts(alerts, in: squad) }
    }

    public func markRead(through seq: Int, in squad: SquadID) async throws(ChatError) {
        try await chat { () throws(APIError) in try await api.markChatRead(through: seq, in: squad) }
    }

    public func unread(in squad: SquadID) async throws(ChatError) -> ChatUnread {
        try await chat { () throws(APIError) in try await api.chatUnread(in: squad) }
    }

    public func characters(in squad: SquadID) async throws(ChatError) -> [MemberID: MemberCharacter] {
        try await chat { () throws(APIError) in
            var characters: [MemberID: MemberCharacter] = [:]
            for mate in try await api.today(of: squad).members {
                characters[mate.member] = mate.character
            }
            return characters
        }
    }

    public func coaches(of squad: SquadID) async throws(ChatError) -> ChatCoaches {
        try await chat { () throws(APIError) in
            let hired = try await api.coach(of: squad).hire?.coach
            // Every coach offered now, for the names on a fired one's messages; one retired since
            // reads as 教练.
            let offered = (try? await api.coaches()) ?? []
            var names = Dictionary(offered.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
            if let hired { names[hired.id] = hired.name }
            return ChatCoaches(current: hired.map { CoachSpeaker(id: $0.id, name: $0.name) }, names: names)
        }
    }

    public func listen(_ heard: @escaping @Sendable (ChatLive) async -> Void) async throws(ChatError) {
        try await chat { () throws(APIError) in try await api.listenForChat(heard) }
    }

    private func chat<T>(_ body: () async throws(APIError) -> T) async throws(ChatError) -> T {
        do throws(APIError) {
            return try await body()
        } catch {
            throw ChatError(error)
        }
    }
}

extension ChatError {
    /// What a failed API call means for the chat.
    init(_ error: APIError) {
        self =
            switch error {
            case .unavailable: .notSent
            case .account(.signedOut), .account(.credentialRejected), .account(.canceled): .signedOut
            case .account: .notSent
            case .refused(.squadNotJoined): .notInSquad
            case .refused(.chatMessageNotFound): .messageGone
            case .refused, .unreadableResponse: .refused
            }
    }
}
