import APIContract
import ChatDomain
import Contracts
import Foundation
import OpenAPIRuntime

// 群聊, the squad's group chat: its pages, sending, reactions, deleting, reporting, the bell's
// alerts and how far the member read, and its live events.
extension WildcardAPI {
    public func chatPage(in squad: SquadID, before: Int?) async throws(APIError) -> ChatPage {
        let wire = try await call {
            try await client.listSquadChat(
                path: .init(squadId: squad.description), query: .init(before: before, limit: ChatPage.limit)
            ).ok.body.json
        }
        return try read { () throws(ContractsError) in try ChatPage(wire) }
    }

    /// Sends the member's message under the id the app picked: the same again is a retry, and
    /// answers the one saved.
    public func send(_ draft: ChatDraft, id: ChatMessageID, in squad: SquadID) async throws(APIError) -> ChatMessage {
        let wire = try await call {
            switch try await client.sendChatMessage(
                path: .init(squadId: squad.description, messageId: id.description), body: .json(draft.wire))
            {
            case .created(let created): return try created.body.json
            case .ok(let saved): return try saved.body.json
            default: throw APIError.unreadableResponse
            }
        }
        return try read { () throws(ContractsError) in try ChatMessage(wire) }
    }

    public func deleteChatMessage(_ id: ChatMessageID, in squad: SquadID) async throws(APIError) {
        try await call {
            _ = try await client.deleteChatMessage(
                path: .init(squadId: squad.description, messageId: id.description)
            ).noContent
        }
    }

    /// Sets the member's emoji on a message, or takes it back when nil.
    public func react(_ emoji: Emoji?, on id: ChatMessageID, in squad: SquadID) async throws(APIError) {
        let path = Operations.ReactToChatMessage.Input.Path(squadId: squad.description, messageId: id.description)
        try await call {
            if let emoji {
                _ = try await client.reactToChatMessage(
                    path: path, body: .json(.init(version: ._1, emoji: emoji.text))
                ).ok
            } else {
                _ = try await client.unreactToChatMessage(path: .init(squadId: path.squadId, messageId: path.messageId))
                    .ok
            }
        }
    }

    public func report(_ id: ChatMessageID, in squad: SquadID) async throws(APIError) {
        try await call {
            _ = try await client.reportChatMessage(
                path: .init(squadId: squad.description, messageId: id.description)
            ).noContent
        }
    }

    public func setChatAlerts(_ alerts: ChatAlerts, in squad: SquadID) async throws(APIError) {
        let wire = Components.Schemas.ChatAlertSettings.AlertsPayload(rawValue: alerts.rawValue) ?? .mentions
        try await call {
            _ = try await client.setChatAlerts(
                path: .init(squadId: squad.description), body: .json(.init(version: ._1, alerts: wire))
            ).ok
        }
    }

    public func markChatRead(through seq: Int, in squad: SquadID) async throws(APIError) {
        try await call {
            _ = try await client.markChatRead(
                path: .init(squadId: squad.description), body: .json(.init(version: ._1, seq: seq))
            ).noContent
        }
    }

    public func chatUnread(in squad: SquadID) async throws(APIError) -> ChatUnread {
        let wire = try await call {
            try await client.getChatUnread(path: .init(squadId: squad.description)).ok.body.json
        }
        return ChatUnread(count: wire.count, mentions: wire.mentions)
    }

    /// Hears the member's live chat events (`GET /viewer/events`) until the server ends the stream.
    public func listenForChat(_ heard: @escaping @Sendable (ChatLive) async -> Void) async throws(APIError) {
        try await call {
            let events = try await live.streamMyEvents().ok.body.textEventStream
            try await Self.readChat(events, heard)
        }
    }

    /// The stream's chat events, in order: `ready`, `chat`, `chatDeleted` and `coachTyping`; any
    /// other is skipped, and so is one this build can't read.
    static func readChat(_ events: HTTPBody, _ heard: @Sendable (ChatLive) async -> Void) async throws {
        for try await event in events.asDecodedServerSentEvents() {
            guard let live = chatEvent(event.event, data: event.data) else { continue }
            await heard(live)
        }
    }

    static func chatEvent(_ name: String?, data: String?) -> ChatLive? {
        if name == "ready" { return .ready }
        guard let data = data?.data(using: .utf8) else { return nil }
        let decoder = DeviceJSON.decoder
        switch name {
        case "chat":
            guard let live = try? decoder.decode(Components.Schemas.LiveChat.self, from: data),
                let squad = UUID(uuidString: live.squadId), let message = try? ChatMessage(live.message)
            else { return nil }
            return .message(SquadID(squad), message, quoted: live.quoted.flatMap { try? ChatMessage($0) })
        case "chatDeleted":
            guard let live = try? decoder.decode(Components.Schemas.LiveChatDeleted.self, from: data),
                let squad = UUID(uuidString: live.squadId), let message = UUID(uuidString: live.messageId)
            else { return nil }
            return .deleted(SquadID(squad), ChatMessageID(message))
        case "coachTyping":
            guard let live = try? decoder.decode(Components.Schemas.LiveCoachTyping.self, from: data),
                let squad = UUID(uuidString: live.squadId), let coach = CoachID(rawValue: live.coachId)
            else { return nil }
            return .coachTyping(SquadID(squad), coach, typing: live.typing)
        default:
            return nil
        }
    }
}

extension ChatPage {
    /// Messages on a page: the API's most.
    static let limit = 50

    init(_ wire: Components.Schemas.ChatPage) throws(ContractsError) {
        let alerts = ChatAlerts(rawValue: wire.alerts.rawValue) ?? .mentions
        self.init(
            messages: try wire.messages.map { wire throws(ContractsError) in try ChatMessage(wire) },
            quoted: try wire.quoted.map { wire throws(ContractsError) in try ChatMessage(wire) },
            more: wire.more, readThrough: wire.readThrough, alerts: alerts)
    }
}

extension ChatMessage {
    init(_ wire: Components.Schemas.ChatMessage) throws(ContractsError) {
        guard let id = UUID(uuidString: wire.id) else { throw .invalidID(wire.id) }
        let author: ChatAuthor
        if let member = wire.member {
            author = .member(try Self.member(member))
        } else if let coach = wire.coachId.flatMap(CoachID.init(rawValue:)) {
            author = .coach(coach)
        } else {
            throw .invalidID(wire.coachId ?? "")
        }
        self.init(
            id: ChatMessageID(id), seq: wire.seq, author: author, kind: wire.kind == .note ? .note : .text,
            text: wire.text, replyTo: wire.replyTo.flatMap(UUID.init(uuidString:)).map(ChatMessageID.init),
            mentions: try wire.mentions.map { text throws(ContractsError) in try Self.member(text) },
            mentionsCoach: wire.mentionsCoach, sentAt: wire.at,
            reactions: try wire.reactions.map { reaction throws(ContractsError) in
                ChatReaction(member: try Self.member(reaction.member), emoji: try Emoji(reaction.emoji))
            })
    }

    private static func member(_ text: String) throws(ContractsError) -> MemberID {
        guard let uuid = UUID(uuidString: text) else { throw .invalidID(text) }
        return MemberID(uuid)
    }
}

extension ChatDraft {
    var wire: Components.Schemas.ChatMessageDraft {
        .init(
            version: ._1, text: text.text, replyTo: replyTo?.description, mentions: mentions.map(\.description),
            mentionsCoach: mentionsCoach)
    }
}
