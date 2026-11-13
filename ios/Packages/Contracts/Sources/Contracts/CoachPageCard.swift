import Foundation

/// The member's answer to a day's challenge (今日挑战): 接受挑战 or 不接挑战.
/// Who marked a day's challenge done.
public enum CoachChallengeCompleter: String, Hashable, Sendable {
    case member, coach
}

public enum CoachChallengeAnswer: String, Hashable, Sendable {
    case accepted, declined

    /// The longest reason a member may give the coach for 不接挑战, in characters; the API checks
    /// the same.
    public static let reasonLimit = 60

    /// A typed reason as it is sent: trimmed and cut to `reasonLimit`, nil when nothing is left.
    public static func reason(_ typed: String) -> String? {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(reasonLimit))
    }
}

/// One thing the squad's coach has for the member on the coach page (Tracy, 2026-11-08): a card in
/// the stack until the member swipes it away (seen), then in 以前. The server keeps which cards
/// were seen, so another phone shows the same stack. The coach's lines to the member's check-ins
/// and replies aren't cards: they stay under the posts in 动态 (Tracy, 2026-11-09).
public struct CoachPageCard: Hashable, Sendable, Identifiable {
    /// What the card is about. The server may add kinds; a card of a kind this build doesn't know
    /// is left out when read.
    public enum Kind: String, Hashable, Sendable, CaseIterable {
        /// 对小队说: the day's 战术板 line to the whole squad.
        case board
        /// 今天对你说: the morning note to the member alone.
        case note
        /// 今日挑战: a challenge in the morning note, which the member accepts or declines once.
        case challenge
        /// 送你的: a piece from the coach's gift pool, unopened until 拆开.
        case gift
    }

    /// A day's challenge: a short title, maybe an amount in the coach's own unit, and the line the
    /// coach says with it.
    public struct Challenge: Hashable, Sendable {
        public let title: String
        public let amount: Int?
        public let unit: String?
        /// The coach to the member, about this challenge (at most 24 characters).
        public let line: String?
        /// Nil until the member answers; the first answer stands.
        public let answer: CoachChallengeAnswer?
        /// Who marked it done, on its own day: the member (我完成了) or the coach, from their
        /// check-ins. Nil until then; the first stands.
        public let completedBy: CoachChallengeCompleter?
        /// Its day is over on the squad's clock (已过期): it is never taken up or marked done after.
        public let isExpired: Bool

        public init(
            title: String, amount: Int? = nil, unit: String? = nil, line: String? = nil,
            answer: CoachChallengeAnswer? = nil, completedBy: CoachChallengeCompleter? = nil,
            isExpired: Bool = false
        ) {
            (self.title, self.amount, self.unit, self.line) = (title, amount, unit, line)
            (self.answer, self.completedBy, self.isExpired) = (answer, completedBy, isExpired)
        }

        /// Still to answer: not answered yet and its day not over.
        public var isOpen: Bool { answer == nil && !isExpired }

        public func answered(_ answer: CoachChallengeAnswer) -> Challenge {
            Challenge(
                title: title, amount: amount, unit: unit, line: line, answer: self.answer ?? answer,
                completedBy: completedBy, isExpired: isExpired)
        }

        public func completed(by completer: CoachChallengeCompleter) -> Challenge {
            Challenge(
                title: title, amount: amount, unit: unit, line: line, answer: answer,
                completedBy: completedBy ?? completer, isExpired: isExpired)
        }

        /// The same challenge once its day is over.
        public func expired() -> Challenge {
            Challenge(
                title: title, amount: amount, unit: unit, line: line, answer: answer,
                completedBy: completedBy, isExpired: true)
        }
    }

    /// A piece the coach gave the member, which only they see.
    public struct Gift: Hashable, Sendable {
        /// The piece's id in the art, such as `gift-sheeptowel`.
        public let piece: String
        /// What the coach said with it; older gifts have none.
        public let line: String?
        /// When the member opened it (拆开); nil while it waits in its box.
        public let openedAt: Date?
        /// Whether they put it on when they opened it (立刻穿上); nil until opened.
        public let worn: Bool?

        public init(piece: String, line: String? = nil, openedAt: Date? = nil, worn: Bool? = nil) {
            (self.piece, self.line, self.openedAt, self.worn) = (piece, line, openedAt, worn)
        }

        public var isOpen: Bool { openedAt != nil }
    }

    public let kind: Kind
    /// Its id within its kind: a note's id for a note or a challenge, the piece for a gift, and so on.
    public let id: String
    public let coach: CoachSpeaker
    /// The coach's character (`CoachCharacter`), such as `xiaohun`; empty for a coach no longer
    /// offered, which stands in as a silhouette.
    public let look: String
    /// When the coach said or gave it.
    public let time: Date
    /// The day it is for, on the squad's clock, for a board line, note or challenge.
    public let day: LocalDay?
    /// What the coach said, for a board line or note.
    public let text: String?
    public let challenge: Challenge?
    public let gift: Gift?
    /// Whether the member has seen it: every card in the stack is unseen, and a card in 以前 may
    /// still be, a coach's that left or one older than the stack keeps.
    public let isSeen: Bool

    public init(
        kind: Kind, id: String, coach: CoachSpeaker, look: String, time: Date, day: LocalDay? = nil,
        text: String? = nil, challenge: Challenge? = nil, gift: Gift? = nil, isSeen: Bool = false
    ) {
        (self.kind, self.id, self.coach, self.look, self.time) = (kind, id, coach, look, time)
        (self.day, self.text, self.challenge, self.gift, self.isSeen) = (day, text, challenge, gift, isSeen)
    }

    /// The same card with its challenge or gift as it stands now, or seen.
    public func with(challenge: Challenge? = nil, gift: Gift? = nil, isSeen: Bool? = nil) -> CoachPageCard {
        CoachPageCard(
            kind: kind, id: id, coach: coach, look: look, time: time, day: day, text: text,
            challenge: challenge ?? self.challenge,
            gift: gift ?? self.gift, isSeen: isSeen ?? self.isSeen)
    }

    /// What tells two cards apart: the same id may stand for a note and its challenge.
    public struct Key: Hashable, Sendable {
        public let kind: Kind
        public let id: String
    }

    public var key: Key { Key(kind: kind, id: id) }
}

/// The coach page's cards: the stack the member hasn't seen, oldest first, and 以前, newest first.
public struct CoachPageCards: Hashable, Sendable {
    public let stack: [CoachPageCard]
    public let earlier: [CoachPageCard]

    public init(stack: [CoachPageCard], earlier: [CoachPageCard]) {
        (self.stack, self.earlier) = (stack, earlier)
    }

    public static let empty = CoachPageCards(stack: [], earlier: [])
}

/// A page of 以前, newest first, and where the next one starts; nil on the last page.
public struct CoachEarlierCards: Hashable, Sendable {
    public let cards: [CoachPageCard]
    public let next: String?

    public init(cards: [CoachPageCard], next: String?) {
        (self.cards, self.next) = (cards, next)
    }
}
