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

    /// 接受挑战 or 算了 on a morning note's challenge; the first answer stands.
    public func answerChallenge(
        of note: Int, in squad: SquadID, with answer: CoachChallengeAnswer
    ) async throws(APIError) -> CoachChallengeAnswer {
        guard let sent = Components.Schemas.CoachChallengeAnswer.AnswerPayload(rawValue: answer.rawValue) else {
            throw .unreadableResponse
        }
        let wire = try await call {
            try await client.answerCoachChallenge(
                path: .init(squadId: squad.description, noteId: note), body: .json(.init(version: ._1, answer: sent))
            ).ok.body.json
        }
        return CoachChallengeAnswer(rawValue: wire.answer.rawValue) ?? answer
    }
}
