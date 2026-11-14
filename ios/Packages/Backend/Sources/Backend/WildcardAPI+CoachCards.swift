import APIContract
import Contracts
import Foundation

// The coach's page: its cards for the member, which they see, open and answer.
extension WildcardAPI {
    /// The member's stack (unseen, oldest first) and 以前 (newest first) in `squad`.
    public func coachCards(in squad: SquadID) async throws(APIError) -> CoachPageCards {
        let wire = try await call {
            try await client.getCoachCards(path: .init(squadId: squad.description)).ok.body.json
        }
        return CoachPageCards(wire)
    }

    /// A page of 以前 in `squad`, newest first, from `cursor` (the page before's `next`); only the
    /// cards not seen yet when `unseenOnly`; every challenge since the member joined when
    /// `challengesOnly`.
    public func earlierCoachCards(
        in squad: SquadID, from cursor: String?, unseenOnly: Bool, challengesOnly: Bool = false
    ) async throws(APIError) -> CoachEarlierCards {
        let wire = try await call {
            try await client.getEarlierCoachCards(
                path: .init(squadId: squad.description),
                query: .init(
                    cursor: cursor, unseen: unseenOnly ? ._true : nil, challenges: challengesOnly ? ._true : nil)
            ).ok.body.json
        }
        return CoachEarlierCards(wire)
    }

    /// Marks a card seen on every phone; a seen note is also put away. Safe to repeat.
    public func markSeen(_ card: CoachPageCard.Key, in squad: SquadID) async throws(APIError) {
        guard let kind = Operations.MarkCoachCardSeen.Input.Path.KindPayload(rawValue: card.kind.rawValue) else {
            throw .unreadableResponse
        }
        _ = try await call {
            try await client.markCoachCardSeen(
                path: .init(squadId: squad.description, kind: kind, cardId: card.id)
            ).ok.body.json
        }
    }

    /// 拆开: the member opened a gift, and put it on now or not. The first opening stands.
    public func openGift(_ piece: String, worn: Bool) async throws(APIError) -> CoachPageCard.Gift {
        let wire = try await call {
            try await client.openGift(path: .init(pieceId: piece), body: .json(.init(version: ._1, worn: worn))).ok
                .body.json
        }
        return CoachPageCard.Gift(wire.gift)
    }

    /// 接受挑战 or 不接挑战 on a morning note's challenge; the first answer stands.
    public func answerChallenge(
        of note: Int, in squad: SquadID, with answer: CoachChallengeAnswer, reason: String?
    ) async throws(APIError) -> CoachChallengeAnswer {
        guard let sent = Components.Schemas.CoachChallengeAnswer.AnswerPayload(rawValue: answer.rawValue) else {
            throw .unreadableResponse
        }
        let wire = try await call {
            try await client.answerCoachChallenge(
                path: .init(squadId: squad.description, noteId: note),
                body: .json(.init(version: ._1, answer: sent, reason: reason))
            ).ok.body.json
        }
        return CoachChallengeAnswer(rawValue: wire.answer.rawValue) ?? answer
    }

    /// Keeps one part of the caller's answer on one card of a coach message they got in `squad`;
    /// the first of each part stands. Gives back everything they answered on it so far.
    public func answerMessage(_ message: String, in squad: SquadID, on path: String, _ part: CoachMessage.Part)
        async throws(APIError) -> [String: CoachMessage.Answered]
    {
        let wire = try await call {
            try await client.answerCoachMessage(
                path: .init(squadId: squad.description, messageId: message), body: .json(part.wire(on: path))
            ).ok.body.json
        }
        return CoachMessage.answered(wire.answered)
    }

    /// The challenge in the caller's morning note today in `squad`, answered or not; nil when
    /// there is none.
    public func todayChallenge(in squad: SquadID) async throws(APIError) -> DayChallenge? {
        let wire = try await call {
            try await client.getCoachChallenge(path: .init(squadId: squad.description)).ok.body.json
        }
        do { return try DayChallenge(wire) } catch { throw .unreadableResponse }
    }

    /// 我完成了 on a morning note's challenge, on its own day; the first completion stands and
    /// comes back.
    public func completeChallenge(of note: Int, in squad: SquadID) async throws(APIError) -> CoachChallengeCompleter {
        let wire = try await call {
            try await client.completeCoachChallenge(
                path: .init(squadId: squad.description, noteId: note), body: .json(.init(version: ._1))
            ).ok.body.json
        }
        return CoachChallengeCompleter(rawValue: wire.completedBy.rawValue) ?? .member
    }
}
