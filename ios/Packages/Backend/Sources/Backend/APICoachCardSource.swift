import Contracts
import Foundation
import SquadDomain

/// The coach's page over our API.
public struct APICoachCardSource: CoachCardSource {
    private let api: WildcardAPI

    public init(api: WildcardAPI) {
        self.api = api
    }

    public func cards(in squad: SquadID) async throws(SquadError) -> CoachPageCards {
        try await coach { () throws(APIError) in try await api.coachCards(in: squad) }
    }

    public func earlier(in squad: SquadID, from cursor: String?, showing filter: CoachDeck.EarlierFilter)
        async throws(SquadError) -> CoachEarlierCards
    {
        try await coach { () throws(APIError) in
            try await api.earlierCoachCards(
                in: squad, from: cursor, unseenOnly: filter == .unseen, challengesOnly: filter == .challenges)
        }
    }

    public func markSeen(_ card: CoachPageCard.Key, in squad: SquadID) async throws(SquadError) {
        try await coach { () throws(APIError) in try await api.markSeen(card, in: squad) }
    }

    public func openGift(_ piece: String, worn: Bool) async throws(SquadError) -> CoachPageCard.Gift {
        try await coach { () throws(APIError) in try await api.openGift(piece, worn: worn) }
    }

    public func answerChallenge(
        _ note: String, in squad: SquadID, with answer: CoachChallengeAnswer, reason: String?
    ) async throws(SquadError) -> CoachChallengeAnswer {
        guard let id = Int(note) else { throw .outdated }
        return try await coach { () throws(APIError) in
            try await api.answerChallenge(of: id, in: squad, with: answer, reason: reason)
        }
    }

    private func coach<T>(_ call: () async throws(APIError) -> T) async throws(SquadError) -> T {
        do {
            return try await call()
        } catch .account(.signedOut), .account(.credentialRejected) {
            throw .signedOut
        } catch .refused(.squadNotJoined) {
            throw .noSquad
        } catch .refused, .unreadableResponse {
            throw .outdated
        } catch {
            throw .unavailable
        }
    }
}
