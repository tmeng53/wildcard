import AvatarArt
import AvatarDomain
import CheckInDomain
import Contracts
import MeDomain
import MeUI
import SquadDomain
import SwiftUI

/// Teammates' player cards, opened from the home's bubble and 小队设置's member list.
extension MainTabs {
    /// A teammate's card in `squad`, read from the API or, on the sample squad, made from the
    /// `characters` the page that opens it already shows.
    func cardModel(
        of member: MemberID, in squad: Squad, characters: [MemberID: MemberCharacter]
    ) -> SquadmateCardModel {
        let looks = characters.mapValues { character in
            MeCharacter(
                nickname: character.nickname.text, outfit: Outfit(character.look), persona: Persona(character.look))
        }
        let cards = squadmateCards ?? InMemorySquadmateCards(characters: { looks[$0] })
        return SquadmateCardModel(member: member, squad: squad.id, squadName: squad.name, cards: cards)
    }

    /// A teammate's card on 小队设置, from the squad and characters that page shows.
    func squadCard(of member: MemberID) -> AnyView {
        AnyView(
            squad.settings.map { settings in
                TeammateCard(model: cardModel(of: member, in: settings.squad, characters: settings.characters))
            })
    }

    /// A teammate's card from the home, which knows the squad once it is read.
    func homeCard(of member: MemberID) -> SquadmateCardModel? {
        guard let home = today.home else { return nil }
        let characters = Dictionary(
            home.today.members.compactMap { mate in mate.character.map { (mate.member, $0) } },
            uniquingKeysWith: { first, _ in first })
        return cardModel(of: member, in: home.squad, characters: characters)
    }
}

/// A teammate's pop-up card, keeping the model it opened with however often its parent draws.
struct TeammateCard: View {
    @State private var model: SquadmateCardModel

    init(model: SquadmateCardModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        SquadmateCardPopup(model: model)
    }
}
