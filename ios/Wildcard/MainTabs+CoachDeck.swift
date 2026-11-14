import CharacterEditorUI
import CheckInUI
import Contracts
import MeDomain
import MeUI
import SquadDomain
import SquadUI
import SwiftUI
import UIKit

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

    /// A link to the coach (`wildcard://coach`): its page, or 教练招聘会 for a squad without a
    /// coach, which has no page to show; the home is read first if it wasn't yet.
    func openCoachOrHiring() {
        selection = .today
        Task {
            if today.home == nil { await today.load() }
            if deckCoach == nil {
                todayPages = [.coach(.market)]
            } else {
                openCoachDeck()
            }
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
            },
            open: { address in openMessageAddress(address) },
            sendFeedback: { [profile] sent in await Self.send(sent, through: profile.feedback) })
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
            mates: today.squadmateCharacters.map { DeckCharacter(look: $0.look, persona: $0.persona) },
            byMember: today.squadCharactersByMember.mapValues { DeckCharacter(look: $0.look, persona: $0.persona) })
    }

    /// A coach message's `open` step: a place in the app by its address, or an https page; an
    /// address this build doesn't know opens nothing.
    private func openMessageAddress(_ address: String) {
        if let destination = AppDestination(address: address) {
            open(destination)
        } else if let url = URL(string: address), url.scheme == "https" {
            UIApplication.shared.open(url)
        }
    }

    /// A coach message's `feedback` step: the box's words as 意见反馈, of the kind it names (an
    /// idea unless it says `problem`); true once they went.
    @MainActor private static func send(_ sent: MessageFeedback, through feedback: any FeedbackService) async -> Bool {
        guard let words = try? FeedbackText(sent.text) else { return false }
        let message = FeedbackMessage(
            id: sent.id, kind: FeedbackKind(rawValue: sent.kind) ?? .idea, text: words, screenshots: [],
            app: FeedbackApp.current)
        do {
            try await feedback.send(message)
            return true
        } catch {
            return false
        }
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
