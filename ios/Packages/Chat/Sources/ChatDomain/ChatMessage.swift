import Contracts
import Foundation

public enum ChatMessageTag {}
/// A chat message's id. The app names a member's own, so sending it again saves it once.
public typealias ChatMessageID = ID<ChatMessageTag>

/// What a member's message says: trimmed, 1 to `maxLength` characters, and it may span lines.
public struct MessageText: Hashable, Sendable {
    /// Characters, counted as people see them. The API's limit.
    public static let maxLength = 500

    public let text: String

    /// Nil for one that is empty once trimmed, or longer than `maxLength`.
    public init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...Self.maxLength).contains(trimmed.count) else { return nil }
        self.text = trimmed
    }
}

/// Who wrote a message: a member, or the squad's coach, which keeps its 教练 tag even after it is
/// fired.
public enum ChatAuthor: Hashable, Sendable {
    case member(MemberID)
    case coach(CoachID)
}

/// A message in the squad's chat, as the server keeps it.
public struct ChatMessage: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        /// Something written.
        case text
        /// The coach's 战术板 line of the day, shown as its card.
        case note
    }

    public let id: ChatMessageID
    /// Its place in the squad's chat, oldest first.
    public let seq: Int
    public let author: ChatAuthor
    public let kind: Kind
    public let text: String
    /// The message it replies to, while that one is there.
    public let replyTo: ChatMessageID?
    public let mentions: [MemberID]
    public let mentionsCoach: Bool
    public let sentAt: Date
    /// Members' reactions, one each, the earliest first.
    public let reactions: [ChatReaction]

    public init(
        id: ChatMessageID, seq: Int, author: ChatAuthor, kind: Kind, text: String, replyTo: ChatMessageID?,
        mentions: [MemberID], mentionsCoach: Bool, sentAt: Date, reactions: [ChatReaction]
    ) {
        (self.id, self.seq, self.author, self.kind, self.text) = (id, seq, author, kind, text)
        (self.replyTo, self.mentions, self.mentionsCoach) = (replyTo, mentions, mentionsCoach)
        (self.sentAt, self.reactions) = (sentAt, reactions)
    }

    /// The member who wrote it, for a member's.
    public var member: MemberID? {
        if case .member(let member) = author { member } else { nil }
    }

    /// The same message with `member`'s reaction set to `emoji`, or taken back when nil.
    func reacting(_ emoji: Emoji?, by member: MemberID) -> ChatMessage {
        var reactions = reactions
        if let index = reactions.firstIndex(where: { $0.member == member }) {
            if let emoji {
                reactions[index] = ChatReaction(member: member, emoji: emoji)
            } else {
                reactions.remove(at: index)
            }
        } else if let emoji {
            reactions.append(ChatReaction(member: member, emoji: emoji))
        }
        return ChatMessage(
            id: id, seq: seq, author: author, kind: kind, text: text, replyTo: replyTo, mentions: mentions,
            mentionsCoach: mentionsCoach, sentAt: sentAt, reactions: reactions)
    }

    /// Each emoji with how many left it, the most first, then the first left first: the count at the
    /// bubble's corner.
    public var reactionCounts: [(emoji: Emoji, count: Int)] {
        var order: [Emoji] = []
        var counts: [Emoji: Int] = [:]
        for reaction in reactions {
            if counts[reaction.emoji] == nil { order.append(reaction.emoji) }
            counts[reaction.emoji, default: 0] += 1
        }
        return order.enumerated()
            .sorted { lhs, rhs in
                let (left, right) = (counts[lhs.element] ?? 0, counts[rhs.element] ?? 0)
                return left == right ? lhs.offset < rhs.offset : left > right
            }
            .map { (emoji: $0.element, count: counts[$0.element] ?? 0) }
    }
}

/// A member's one emoji on a message.
public struct ChatReaction: Hashable, Sendable {
    public let member: MemberID
    public let emoji: Emoji

    public init(member: MemberID, emoji: Emoji) {
        self.member = member
        self.emoji = emoji
    }
}

/// When the member gets a push for this squad's messages (the bell in the chat's header).
public enum ChatAlerts: String, CaseIterable, Hashable, Sendable {
    /// When someone @s them or replies to them: the default.
    case mentions
    /// Every message.
    case all
    /// Never.
    case none
}

/// A page of the chat, as the server sends it.
public struct ChatPage: Hashable, Sendable {
    /// Newest first.
    public let messages: [ChatMessage]
    /// The messages those reply to that aren't among them.
    public let quoted: [ChatMessage]
    /// Whether older messages come before these.
    public let more: Bool
    /// How far the member read, a `seq`; 0 before they read any.
    public let readThrough: Int
    public let alerts: ChatAlerts

    public init(messages: [ChatMessage], quoted: [ChatMessage], more: Bool, readThrough: Int, alerts: ChatAlerts) {
        (self.messages, self.quoted, self.more, self.readThrough, self.alerts) =
            (messages, quoted, more, readThrough, alerts)
    }
}

/// What the member hasn't read: the count on the button beside 打卡.
public struct ChatUnread: Hashable, Sendable {
    public let count: Int
    /// Those of them that @ the member or reply to them.
    public let mentions: Int

    public init(count: Int, mentions: Int) {
        self.count = count
        self.mentions = mentions
    }

    public static let none = ChatUnread(count: 0, mentions: 0)
}

/// A message the member is sending.
public struct ChatDraft: Hashable, Sendable {
    public let text: MessageText
    public let replyTo: ChatMessageID?
    public let mentions: [MemberID]
    public let mentionsCoach: Bool

    public init(text: MessageText, replyTo: ChatMessageID?, mentions: [MemberID], mentionsCoach: Bool) {
        (self.text, self.replyTo, self.mentions, self.mentionsCoach) = (text, replyTo, mentions, mentionsCoach)
    }
}

/// What the member's open app hears about a squad's chat while it is in front.
public enum ChatLive: Hashable, Sendable {
    /// The stream is open: anything sent while it was closed is read again.
    case ready
    /// A message new to the chat, or whose reactions changed, with the one it replies to.
    case message(SquadID, ChatMessage, quoted: ChatMessage?)
    /// A message was deleted.
    case deleted(SquadID, ChatMessageID)
    /// The coach is writing (its three dots), or stopped.
    case coachTyping(SquadID, CoachID, typing: Bool)
}
