import Contracts
import Foundation

/// Whom a comment can @: the squad's coach, first, and the people who see the post.
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

    public var isCoach: Bool {
        if case .coach = self { true } else { false }
    }

    /// What picking it puts in the words: `@` and its name, then a space.
    public var token: String { "@\(name) " }
}

/// What the comment box holds: the words and whom the member picked to @. The @s that count are
/// those still in the words, so deleting 「@毛头」 takes it back.
public struct CommentDraft: Hashable, Sendable {
    public var text = ""
    public private(set) var picked: [Mentionable] = []

    public init() {}

    /// Whom the picker shows for the words after the `@` being typed: the coach first while the
    /// squad has one, then `people` (never the viewer), each whose name starts with what was typed,
    /// and none already picked past the limit.
    public static func candidates(
        for query: String, coach: CoachSpeaker?, people: [MemberID: String], viewer: MemberID
    ) -> [Mentionable] {
        let mates = people.filter { $0.key != viewer }
            .map { Mentionable.member($0.key, name: $0.value) }
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

    /// Whom the comment @s: those picked whose 「@名字」 is still in the words, up to the limit.
    public var mentions: Mentions {
        let kept = picked.filter { text.contains("@\($0.name)") }
        let members = kept.compactMap { mention -> MemberID? in
            if case .member(let member, _) = mention { member } else { nil }
        }
        let coach = kept.lazy.compactMap { mention -> CoachID? in
            if case .coach(let coach) = mention { coach.id } else { nil }
        }.first
        return Mentions(members: members, coach: coach)
    }

    /// Whether it has room to @ one more member.
    public var canMentionMore: Bool { mentions.members.count < Mentions.maxMembers }

    /// After sending: empty again.
    public mutating func clear() { self = CommentDraft() }
}
