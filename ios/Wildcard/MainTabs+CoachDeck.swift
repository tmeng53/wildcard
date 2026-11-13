import CharacterEditorUI
import CheckInUI
import Contracts
import SquadDomain
import SquadUI
import SwiftUI

/// The coach's page (Tracy, 2026-11-08), pushed over 今天 from a tap on the coach, a morning
/// note's 通知 row or its push: its cards for the member, 以前 and a card opened from there.
extension MainTabs {
    /// 今天's coach opens its page, and the coach's head on today's challenge that challenge's card.
    func opensCoachPagesFromToday() {
        today.openCoach = { openCoachDeck() }
        today.openChallenge = { openChallengeCard($0) }
    }

    /// Opens the card of today's challenge, from a tap on its coach's head on the squad card (Tracy,
    /// 2026-11-10): over the coach's page, so 返回 lands there; the page alone when the card can't
    /// be read.
    func openChallengeCard(_ challenge: DayChallenge) {
        guard let deck = readyDeck() else {
            openCoachDeck()
            return
        }
        Task {
            let card = await deck.challengeCard(note: challenge.note)
            // The member hasn't gone elsewhere while it was read.
            guard selection == .today, todayPages.isEmpty else { return }
            // A coach fired since keeps its card, though the squad has no page for it.
            let page: [TodayPage] = deckCoach == nil ? [] : [.coachDeck]
            todayPages = page + (card.map { [.coachCard($0)] } ?? [])
        }
    }

    /// Opens the coach's page on 今天, made for the squad 今天 is on.
    func openCoachDeck() {
        // A note's 通知 row or push can come before 今天 was ever shown (the app opened on 动态,
        // or from the push itself), so its home isn't read yet: read it, then open the page.
        guard readyDeck() != nil else {
            selection = .today
            Task {
                await today.load()
                if today.squadID != nil { openCoachDeck() }
            }
            return
        }
        selection = .today
        todayPages = [.coachDeck]
    }

    /// The coach's cards for the squad 今天 is on, kept while it stays on it; nil until 今天 is read.
    private func readyDeck() -> CoachDeck? {
        guard let squadID = today.squadID else { return nil }
        if let open = coachDeck, open.squad == squadID { return open }
        let deck = CoachDeck(
            squad: squadID, source: coachCards,
            wear: { [wardrobe] piece in await wardrobe.wear(piece) },
            changed: { [profile, today] in
                Task {
                    await profile.reload()
                    await today.reloadCoach()
                }
            })
        coachDeck = deck
        return deck
    }

    /// The coach's page, 以前 or one card from it.
    @ViewBuilder func coachDeckPage(_ page: TodayPage) -> some View {
        if let deck = coachDeck {
            switch page {
            case .coachDeck:
                if let coach = deckCoach {
                    CoachDeckPage(
                        deck: deck, coach: coach, coachLook: coach.id.rawValue, cast: deckCast,
                        places: deckPlaces)
                }
            case .coachEarlier:
                CoachEarlierPage(deck: deck, places: deckPlaces) { todayPages.append(.coachCard($0)) }
            case .coachCard(let card):
                CoachCardPage(deck: deck, card: card, cast: deckCast, places: deckPlaces)
            case .squad, .coach, .place, .post:
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
