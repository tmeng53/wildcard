import Contracts
import Foundation

// Reading the coach's page from the API's wire types.

extension CoachPageCards {
    /// A card of a kind this build doesn't know, or one it can't read, is left out.
    public init(_ wire: Components.Schemas.CoachCards) {
        self.init(
            stack: wire.stack.compactMap { try? CoachPageCard($0) },
            earlier: wire.earlier.compactMap { try? CoachPageCard($0) })
    }
}

extension CoachPageCard {
    public init(_ wire: Components.Schemas.CoachPageCard) throws(ContractsError) {
        guard let kind = Kind(rawValue: wire.kind) else { throw .invalidID(wire.kind) }
        let challenge = wire.challenge.map(\.value1).map { wire in
            Challenge(
                title: wire.title, amount: wire.amount, unit: wire.unit, line: wire.line,
                answer: wire.answer.flatMap { CoachChallengeAnswer(rawValue: $0.rawValue) })
        }
        let gift = wire.gift.map {
            Gift(piece: $0.pieceId, line: $0.line, openedAt: $0.openedAt, worn: $0.worn)
        }
        self.init(
            kind: kind, id: wire.id, coach: try CoachSpeaker(wire.coach), look: wire.coach.look, time: wire.at,
            day: try wire.day.map { day throws(ContractsError) in try LocalDay(day) }, text: wire.text,
            challenge: challenge, gift: gift,
            checkIn: try wire.checkInId.map { id throws(ContractsError) in try CheckInID(wire: id) },
            comment: try wire.commentId.map { id throws(ContractsError) in try CommentID(wire: id) })
    }
}

extension CoachPageCard.Gift {
    public init(_ wire: Components.Schemas.GiftedPiece) {
        self.init(piece: wire.id, line: wire.line, openedAt: wire.openedAt, worn: wire.worn)
    }
}
