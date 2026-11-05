import Contracts
import Foundation

/// Whom a message can @: the squad's coach, first, and the member's squadmates.
public enum Mentionable: Hashable, Sendable, Identifiable {
    case coach(CoachSpeaker)
    case member(MemberID, name: String)

    public var id: String {
        switch self {
        case .coach(let coach): "coach.\(coach.id.rawValue)"
        case .member(let member, _): "member.\(member)"
        }
    }

    public var name: String {
        switch self {
        case .coach(let coach): coach.name
        case .member(_, let name): name
        }
    }

    /// What picking it puts in the message: `@` and its name, then a space.
    public var token: String { "@\(name) " }
}

/// What the composer holds: the words, whom the member picked to @ and the message they reply to.
/// The @s that count are those still in the words, so deleting 「@毛头」 takes it back.
public struct ChatComposer: Hashable, Sendable {
    public var text = ""
    public var replyTo: ChatMessageID?
    public private(set) var picked: [Mentionable] = []

    public init() {}

    /// Whom the picker shows for the words after the last `@`: the coach first while the squad has
    /// one, then squadmates (never the member), each whose name starts with what was typed.
    public static func candidates(
        for query: String, coach: CoachSpeaker?, characters: [MemberID: MemberCharacter], viewer: MemberID
    ) -> [Mentionable] {
        let mates = characters.filter { $0.key != viewer }
            .map { Mentionable.member($0.key, name: $0.value.nickname.text) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let all = (coach.map { [Mentionable.coach($0)] } ?? []) + mates
        guard !query.isEmpty else { return all }
        return all.filter { $0.name.lowercased().hasPrefix(query.lowercased()) }
    }

    /// The words after an `@` the member is typing at the end, nil while they aren't typing one.
    public var mentionQuery: String? {
        guard let sign = text.lastIndex(of: "@") else { return nil }
        let after = text[text.index(after: sign)...]
        guard !after.contains(where: \.isWhitespace) else { return nil }
        return String(after)
    }

    /// Puts `mention` in place of the `@` being typed, or at the end (the 「@毛头」 button).
    public mutating func pick(_ mention: Mentionable) {
        if mentionQuery != nil, let sign = text.lastIndex(of: "@") {
            text = String(text[..<sign])
        } else if let last = text.last, !last.isWhitespace {
            text += " "
        }
        text += mention.token
        if !picked.contains(mention) { picked.append(mention) }
    }

    /// The message to send, nil while there is nothing to send.
    public var draft: ChatDraft? {
        guard let words = MessageText(text) else { return nil }
        let kept = picked.filter { text.contains("@\($0.name)") }
        let members = kept.compactMap { mention -> MemberID? in
            if case .member(let member, _) = mention { member } else { nil }
        }
        let coach = kept.contains { if case .coach = $0 { true } else { false } }
        return ChatDraft(text: words, replyTo: replyTo, mentions: members, mentionsCoach: coach)
    }

    /// After sending: empty again.
    public mutating func clear() { self = ChatComposer() }
}
