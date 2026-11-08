import CharacterEditorUI
import CheckInUI
import Contracts
import SquadDomain
import SquadUI
import SwiftUI

/// The coach's page (Tracy, 2026-11-08), pushed over 今天 from a tap on the coach, a morning
/// note's 通知 row or its push: its cards for the member, 以前 and a card opened from there.
extension MainTabs {
    /// Opens the coach's page on 今天, made for the squad 今天 is on.
    func openCoachDeck() {
        guard let squadID = today.squadID else { return }
        if coachDeck?.squad != squadID {
            coachDeck = CoachDeck(
                squad: squadID, source: coachCards,
                wear: { [wardrobe] piece in await wardrobe.wear(piece) },
                changed: { [profile, today] in
                    Task {
                        await profile.reload()
                        await today.reloadCoach()
                    }
                })
        }
        selection = .today
        todayPages = [.coachDeck]
    }

    /// The coach's page, 以前 or one card from it.
    @ViewBuilder func coachDeckPage(_ page: TodayPage) -> some View {
        if let deck = coachDeck, let coach = deckCoach {
            switch page {
            case .coachDeck:
                CoachDeckPage(
                    deck: deck, coach: coach, coachLook: coach.id.rawValue, cast: deckCast,
                    places: deckPlaces)
            case .coachEarlier:
                CoachEarlierPage(deck: deck, places: deckPlaces) { todayPages.append(.coachCard($0)) }
            case .coachCard(let card):
                CoachCardPage(deck: deck, card: card, cast: deckCast, places: deckPlaces)
            case .squad, .coach:
                EmptyView()
            }
        }
    }

    /// The squad's coach, for the page's title and its last card; the sideline's until 小队 is read.
    private var deckCoach: CoachSpeaker? {
        squad.coach.map { CoachSpeaker(id: $0.coach.id, name: $0.coach.name) } ?? today.sidelineCoach
    }

    /// The member, and the rest of the squad for a line to everyone.
    private var deckCast: DeckCast {
        let mine = today.myCharacter
        return DeckCast(
            member: DeckCharacter(look: mine.look, persona: mine.persona),
            mates: today.squadmateCharacters.map { DeckCharacter(look: $0.look, persona: $0.persona) })
    }

    private var deckPlaces: CoachDeckPlaces {
        CoachDeckPlaces(
            feed: { selection = .feed },
            post: { open(.post($0)) },
            wardrobe: { piece in
                selection = .profile
                closeProfilePages()
                Task { await wardrobe.showGift(piece) }
            },
            market: { todayPages.append(.coach(.market)) },
            resume: {
                guard let hire = squad.coach else { return }
                todayPages.append(.coach(.resume(hire.coach)))
            },
            earlier: { todayPages.append(.coachEarlier) },
            giftPicture: { AnyView(WardrobePicture(.piece, item: $0)) },
            giftName: { UnlockNames.piece($0) })
    }
}
