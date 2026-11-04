import Contracts
import Observation

/// A squadmate's player card in its sheet, opened from their name on the home or in 小队设置:
/// read once when it opens, and again on a retry. It has nothing to change.
@MainActor @Observable
public final class SquadmateCardModel {
    public enum Load: Hashable, Sendable {
        case loading
        case loaded(PlayerCardFace)
        case failed(MeError)
    }

    public private(set) var load: Load = .loading
    public let member: MemberID
    public let squad: SquadID
    /// Their squad's name, for the card's front.
    private let squadName: String?
    @ObservationIgnored private let cards: any SquadmateCards

    public init(member: MemberID, squad: SquadID, squadName: String?, cards: any SquadmateCards) {
        (self.member, self.squad, self.squadName, self.cards) = (member, squad, squadName, cards)
    }

    /// Reads the card; after a failure, shows it failed until the next try.
    public func reload() async {
        do {
            var card = try await cards.card(of: member, in: squad)
            card.squadName = card.squadName ?? squadName
            load = .loaded(card)
        } catch {
            if case .loaded = load { return }
            load = .failed(error)
        }
    }
}
