import Contracts
import Foundation
import SquadDomain
import Synchronization
import Testing

private let deckSquad = SquadID(UUID(uuidString: "5a000000-0000-4000-8000-0000000000c1") ?? UUID())
private let maotouSpeaker = CoachSpeaker(id: "xiaohun", name: "毛头")
private let morning = Date(timeIntervalSince1970: 1_794_150_000)

private func card(
    _ kind: CoachPageCard.Kind, _ id: String, minutes: Double, text: String? = nil,
    challenge: CoachPageCard.Challenge? = nil, gift: CoachPageCard.Gift? = nil
) -> CoachPageCard {
    CoachPageCard(
        kind: kind, id: id, coach: maotouSpeaker, look: "xiaohun", time: morning.addingTimeInterval(minutes * 60),
        text: text, challenge: challenge, gift: gift)
}

/// The coach's cards kept in memory, with what was asked of it.
private final class CardsInMemory: CoachCardSource {
    struct State {
        var cards: CoachPageCards
        var seen: [CoachPageCard.Key] = []
        var opened: [(piece: String, worn: Bool)] = []
        var answers: [String: CoachChallengeAnswer] = [:]
        var reasons: [String?] = []
        var down = false
    }

    let state: Mutex<State>

    init(_ cards: CoachPageCards) { state = Mutex(State(cards: cards)) }

    func cards(in squad: SquadID) async throws(SquadError) -> CoachPageCards {
        try state.withLock { state throws(SquadError) in
            if state.down { throw .unavailable }
            return state.cards
        }
    }

    func markSeen(_ card: CoachPageCard.Key, in squad: SquadID) async throws(SquadError) {
        state.withLock { $0.seen.append(card) }
    }

    func openGift(_ piece: String, worn: Bool) async throws(SquadError) -> CoachPageCard.Gift {
        try state.withLock { state throws(SquadError) in
            if state.down { throw .unavailable }
            state.opened.append((piece, worn))
            return CoachPageCard.Gift(piece: piece, line: "练完擦汗。", openedAt: morning, worn: worn)
        }
    }

    func answerChallenge(
        _ note: String, in squad: SquadID, with answer: CoachChallengeAnswer, reason: String?
    ) async throws(SquadError) -> CoachChallengeAnswer {
        state.withLock { state in
            state.reasons.append(reason)
            let standing = state.answers[note] ?? answer
            state.answers[note] = standing
            return standing
        }
    }
}

private let board = card(.board, "b1", minutes: 0, text: "这周还差 6 天，周日前补上。")
private let gift = card(
    .gift, "gift-sheeptowel", minutes: 1, gift: CoachPageCard.Gift(piece: "gift-sheeptowel", line: "练完擦汗。"))
private let stretch = card(
    .challenge, "41", minutes: 2,
    challenge: CoachPageCard.Challenge(title: "拉伸", amount: 5, unit: "分钟", line: "昨天跑完腿还紧，睡前拉一拉。"))
private let oldReply = card(.reply, "r0", minutes: -1440, text: "配速比上周快了。")

@MainActor @Test func theStackShowsTheOldestUnseenCardOnTop() async {
    let deck = CoachDeck(
        squad: deckSquad, source: CardsInMemory(CoachPageCards(stack: [board, gift, stretch], earlier: [oldReply])))
    #expect(deck.load == .loading)
    await deck.reload()
    #expect(deck.load == .loaded)
    #expect(deck.top == board)
    #expect(deck.earlier == [oldReply])
}

@MainActor @Test func aSwipeMovesTheCardIntoEarlierAndMarksItSeen() async throws {
    let source = CardsInMemory(CoachPageCards(stack: [board, gift], earlier: [oldReply]))
    let deck = CoachDeck(squad: deckSquad, source: source)
    await deck.reload()
    deck.seen(board)
    #expect(deck.top == gift)
    #expect(deck.earlier.map(\.id) == ["b1", "r0"])
    #expect(deck.putAway == 1)
    try await Task.sleep(for: .milliseconds(50))
    #expect(source.state.withLock(\.seen) == [board.key])
    // A read that was on its way before the swipe doesn't bring it back.
    await deck.reload()
    #expect(deck.top == gift)
    #expect(deck.earlier.map(\.id) == ["b1", "r0"])
    deck.seen(gift)
    #expect(deck.top == nil)
}

@MainActor @Test func openingAGiftToWearItPutsItOn() async {
    let source = CardsInMemory(CoachPageCards(stack: [gift], earlier: []))
    let worn = Mutex<[String]>([])
    var changes = 0
    let deck = CoachDeck(
        squad: deckSquad, source: source, wear: { piece in worn.withLock { $0.append(piece) } },
        changed: { changes += 1 })
    await deck.reload()
    #expect(await deck.open(gift, worn: true))
    #expect(deck.top?.gift?.isOpen == true)
    #expect(deck.top?.gift?.worn == true)
    #expect(worn.withLock(\.self) == ["gift-sheeptowel"])
    #expect(changes == 1)
}

@MainActor @Test func aGiftPutAsideIsOpenedButNotWorn() async {
    let source = CardsInMemory(CoachPageCards(stack: [gift], earlier: []))
    let worn = Mutex<[String]>([])
    let deck = CoachDeck(squad: deckSquad, source: source, wear: { piece in worn.withLock { $0.append(piece) } })
    await deck.reload()
    #expect(await deck.open(gift, worn: false))
    #expect(deck.top?.gift?.worn == false)
    #expect(worn.withLock(\.self) == [])
}

/// An unopened gift swiped away waits in 以前 in its box and opens from there.
@MainActor @Test func aBoxedGiftOpensFromEarlier() async {
    let deck = CoachDeck(squad: deckSquad, source: CardsInMemory(CoachPageCards(stack: [gift], earlier: [])))
    await deck.reload()
    deck.seen(gift)
    #expect(deck.earlier.first?.gift?.isOpen == false)
    #expect(await deck.open(gift, worn: false))
    #expect(deck.earlier.first?.gift?.isOpen == true)
    #expect(deck.current(gift).gift?.isOpen == true)
}

@MainActor @Test func aGiftThatCouldntOpenSaysSoAndStaysBoxed() async {
    let source = CardsInMemory(CoachPageCards(stack: [gift], earlier: []))
    let deck = CoachDeck(squad: deckSquad, source: source)
    await deck.reload()
    source.state.withLock { $0.down = true }
    #expect(!(await deck.open(gift, worn: true)))
    #expect(deck.failed == gift.key)
    #expect(deck.top?.gift?.isOpen == false)
    #expect(deck.sending.isEmpty)
}

@MainActor @Test func aChallengeIsAnsweredOnce() async {
    let deck = CoachDeck(squad: deckSquad, source: CardsInMemory(CoachPageCards(stack: [stretch], earlier: [])))
    await deck.reload()
    await deck.answer(stretch, .accepted)
    #expect(deck.top?.challenge?.answer == .accepted)
    await deck.answer(deck.current(stretch), .declined)
    #expect(deck.top?.challenge?.answer == .accepted)
}

@MainActor @Test(arguments: [
    (CoachChallengeAnswer.declined, "  我鸡蛋过敏 \n", "我鸡蛋过敏" as String?),
    (.declined, "   ", nil),
    (.accepted, "我鸡蛋过敏", nil),
])
func onlyADeclineSendsWhatWasTyped(answer: CoachChallengeAnswer, typed: String, sent: String?) async {
    let source = CardsInMemory(CoachPageCards(stack: [stretch], earlier: []))
    let deck = CoachDeck(squad: deckSquad, source: source)
    await deck.reload()
    await deck.answer(stretch, answer, reason: typed)
    #expect(source.state.withLock { $0.reasons } == [sent])
}

@Test func aReasonIsCutToTheLimit() {
    #expect(CoachChallengeAnswer.reason(String(repeating: "蛋", count: 70)) == String(repeating: "蛋", count: 60))
}

@MainActor @Test func aFailedFirstReadSaysSo() async {
    let source = CardsInMemory(CoachPageCards(stack: [board], earlier: []))
    source.state.withLock { $0.down = true }
    let deck = CoachDeck(squad: deckSquad, source: source)
    await deck.reload()
    #expect(deck.load == .failed(.unavailable))
    source.state.withLock { $0.down = false }
    await deck.reload()
    #expect(deck.top == board)
}
