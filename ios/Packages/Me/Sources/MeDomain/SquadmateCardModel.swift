import Contracts
import Observation

/// A player's card in its pop-up, opened from their name on the home or in 小队: read once when it
/// opens, and again on a retry. A squadmate's has nothing to change; the member's own wears a
/// title from its badges, through 我's model, so 我 shows the same one.
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
    /// 我's model when the card is the member's own; nil on a squadmate's.
    @ObservationIgnored private let own: MeModel?

    /// `own` is 我's model when `member` is the member themselves, so their badges can be worn.
    public init(
        member: MemberID, squad: SquadID, squadName: String?, cards: any SquadmateCards, own: MeModel? = nil
    ) {
        (self.member, self.squad, self.squadName, self.cards, self.own) = (member, squad, squadName, cards, own)
    }

    /// The member's own card, whose badges have 装备.
    public var canEquip: Bool { own != nil }

    /// Wears a title or team badge on this card at once and saves it as 我 does; puts the one
    /// worn before back if saving fails. Does nothing on a squadmate's card.
    public func equip(_ wearable: Wearable) async {
        guard let own, case .loaded(var face) = load else { return }
        let before = (face.board.worn, face.board.wornTeamBadge)
        face.board.wear(wearable)
        load = .loaded(face)
        let saved = await own.equip(wearable)
        guard case .loaded(var latest) = load else { return }
        // Only what is worn: this card's board lists what this squad's route sent.
        (latest.board.worn, latest.board.wornTeamBadge) = saved.map { ($0.worn, $0.wornTeamBadge) } ?? before
        load = .loaded(latest)
    }

    /// Reads the card; after a failure, shows it failed until the next try, which shows the
    /// loader again.
    public func reload() async {
        if case .failed = load { load = .loading }
        do {
            var card = try await cards.card(of: member, in: squad)
            card.squadName = card.squadName ?? squadName
            load = .loaded(card)
        } catch {
            // Closed before the card came, it didn't fail.
            guard !Task.isCancelled else { return }
            if case .loaded = load { return }
            load = .failed(error)
        }
    }
}
