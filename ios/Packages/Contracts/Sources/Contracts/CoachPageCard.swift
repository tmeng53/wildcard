import Foundation

/// The member's answer to a day's challenge (今日挑战): 接受挑战 or 算了.
public enum CoachChallengeAnswer: String, Hashable, Sendable {
    case accepted, declined
}

/// One thing the squad's coach has for the member on the coach page (Tracy, 2026-11-08): a card in
/// the stack until the member swipes it away (seen), then in 以前. The server keeps which cards
/// were seen, so another phone shows the same stack.
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
        /// 回复了你的训练: the coach's line under the member's check-in.
        case reply
        /// 回复了你: the coach's answer to the member's reply to it.
        case answer
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

        public init(
            title: String, amount: Int? = nil, unit: String? = nil, line: String? = nil,
            answer: CoachChallengeAnswer? = nil
        ) {
            (self.title, self.amount, self.unit, self.line, self.answer) = (title, amount, unit, line, answer)
        }

        public func answered(_ answer: CoachChallengeAnswer) -> Challenge {
            Challenge(title: title, amount: amount, unit: unit, line: line, answer: self.answer ?? answer)
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
    /// What the coach said, for a board line, note, reply or answer.
    public let text: String?
    public let challenge: Challenge?
    public let gift: Gift?
    /// The member's check-in a reply or answer is under.
    public let checkIn: CheckInID?
    /// The member's reply an answer answers.
    public let comment: CommentID?

    public init(
        kind: Kind, id: String, coach: CoachSpeaker, look: String, time: Date, day: LocalDay? = nil,
        text: String? = nil,
        challenge: Challenge? = nil, gift: Gift? = nil, checkIn: CheckInID? = nil, comment: CommentID? = nil
    ) {
        (self.kind, self.id, self.coach, self.look, self.time) = (kind, id, coach, look, time)
        (self.day, self.text) = (day, text)
        (self.challenge, self.gift, self.checkIn, self.comment) = (challenge, gift, checkIn, comment)
    }

    /// The same card with its challenge or gift as it stands now.
    public func with(challenge: Challenge? = nil, gift: Gift? = nil) -> CoachPageCard {
        CoachPageCard(
            kind: kind, id: id, coach: coach, look: look, time: time, day: day, text: text,
            challenge: challenge ?? self.challenge,
            gift: gift ?? self.gift, checkIn: checkIn, comment: comment)
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
