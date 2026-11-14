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
        var filters: [CoachDeck.EarlierFilter] = []
        var down = false
        /// The challenges' day is over on the server.
        var dayOver = false
        /// What the member answered on coach messages, by path; the first part stands.
        var messageAnswers: [String: CoachMessage.Answered] = [:]
        var parts: [(path: String, part: CoachMessage.Part)] = []
    }

    let state: Mutex<State>

    init(_ cards: CoachPageCards) { state = Mutex(State(cards: cards)) }

    func cards(in squad: SquadID) async throws(SquadError) -> CoachPageCards {
        try state.withLock { state throws(SquadError) in
            if state.down { throw .unavailable }
            return state.cards
        }
    }

    func earlier(in squad: SquadID, from cursor: String?, showing filter: CoachDeck.EarlierFilter)
        async throws(SquadError) -> CoachEarlierCards
    {
        try state.withLock { state throws(SquadError) in
            if state.down { throw .unavailable }
            state.filters.append(filter)
            let listed =
                switch filter {
                case .all: state.cards.earlier
                case .unseen: state.cards.earlier.filter { !$0.isSeen }
                case .challenges: (state.cards.stack.reversed() + state.cards.earlier).filter { $0.kind == .challenge }
                }
            let start = cursor.flatMap { after in listed.firstIndex { $0.id == after } }.map { $0 + 1 } ?? 0
            let page = Array(listed.dropFirst(start).prefix(2))
            return CoachEarlierCards(cards: page, next: start + 2 < listed.count ? page.last?.id : nil)
        }
    }

    func markSeen(_ card: CoachPageCard.Key, in squad: SquadID) async throws(SquadError) {
        try state.withLock { state throws(SquadError) in
            if state.down { throw .unavailable }
            state.seen.append(card)
        }
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
        try state.withLock { state throws(SquadError) in
            if state.dayOver && state.answers[note] == nil { throw .challengeExpired }
            state.reasons.append(reason)
            let standing = state.answers[note] ?? answer
            state.answers[note] = standing
            return standing
        }
    }

    func answerMessage(_ message: String, in squad: SquadID, on path: String, _ part: CoachMessage.Part)
        async throws(SquadError) -> [String: CoachMessage.Answered]
    {
        try state.withLock { state throws(SquadError) in
            if state.down { throw .unavailable }
            state.parts.append((path, part))
            let was = state.messageAnswers[path] ?? CoachMessage.Answered()
            state.messageAnswers[path] =
                switch part {
                case .tap(let button): CoachMessage.Answered(tap: was.tap ?? button, stars: was.stars, text: was.text)
                case .stars(let stars): CoachMessage.Answered(tap: was.tap, stars: was.stars ?? stars, text: was.text)
                case .text(let text): CoachMessage.Answered(tap: was.tap, stars: was.stars, text: was.text ?? text)
                }
            return state.messageAnswers
        }
    }
}

private let board = card(.board, "b1", minutes: 0, text: "这周还差 6 天，周日前补上。")
private let gift = card(
    .gift, "gift-sheeptowel", minutes: 1, gift: CoachPageCard.Gift(piece: "gift-sheeptowel", line: "练完擦汗。"))
private let stretch = card(
    .challenge, "41", minutes: 2,
    challenge: CoachPageCard.Challenge(title: "拉伸", amount: 5, unit: "分钟", line: "昨天跑完腿还紧，睡前拉一拉。"))
private let oldNote = card(.note, "40", minutes: -1440, text: "昨天跑完 5 公里，今天随便动动。")

@MainActor @Test func theStackShowsTheOldestUnseenCardOnTop() async {
    let deck = CoachDeck(
        squad: deckSquad, source: CardsInMemory(CoachPageCards(stack: [board, gift, stretch], earlier: [oldNote])))
    #expect(deck.load == .loading)
    await deck.reload()
    #expect(deck.load == .loaded)
    #expect(deck.top == board)
    #expect(deck.earlier == [oldNote])
}

@MainActor @Test func aSwipeMovesTheCardIntoEarlierAndMarksItSeen() async throws {
    let source = CardsInMemory(CoachPageCards(stack: [board, gift], earlier: [oldNote]))
    let deck = CoachDeck(squad: deckSquad, source: source)
    await deck.reload()
    deck.seen(board)
    #expect(deck.top == gift)
    #expect(deck.earlier.map(\.id) == ["b1", "40"])
    #expect(deck.putAway == 1)
    try await Task.sleep(for: .milliseconds(50))
    #expect(source.state.withLock(\.seen) == [board.key])
    // A read that was on its way before the swipe doesn't bring it back.
    await deck.reload()
    #expect(deck.top == gift)
    #expect(deck.earlier.map(\.id) == ["b1", "40"])
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

@MainActor @Test func anExpiredChallengeIsNeverTakenUp() async {
    let expired = stretch.with(challenge: stretch.challenge?.expired())
    let source = CardsInMemory(CoachPageCards(stack: [], earlier: [expired]))
    let deck = CoachDeck(squad: deckSquad, source: source)
    await deck.reload()
    #expect(expired.challenge?.isOpen == false)
    await deck.answer(expired, .accepted)
    #expect(source.state.withLock { $0.reasons }.isEmpty)
    #expect(deck.current(expired).challenge?.answer == nil)
}

@MainActor @Test func aChallengeWhoseDayEndedWhileThePageWasOpenShowsExpired() async {
    let source = CardsInMemory(CoachPageCards(stack: [stretch], earlier: []))
    let deck = CoachDeck(squad: deckSquad, source: source)
    await deck.reload()
    source.state.withLock { $0.dayOver = true }
    await deck.answer(stretch, .accepted)
    #expect(deck.top?.challenge?.answer == nil)
    #expect(deck.top?.challenge?.isExpired == true)
    #expect(deck.failed == nil)
}

@MainActor
@Test(arguments: [
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

@MainActor @Test func aCardSwipedAwayOfflineIsMarkedSeenOnTheNextRead() async throws {
    let source = CardsInMemory(CoachPageCards(stack: [board, gift], earlier: []))
    let deck = CoachDeck(squad: deckSquad, source: source)
    await deck.reload()
    source.state.withLock { $0.down = true }
    deck.seen(board)
    try await Task.sleep(for: .milliseconds(50))
    #expect(source.state.withLock(\.seen).isEmpty)
    #expect(deck.earlier.map(\.key) == [board.key])
    source.state.withLock { $0.down = false }
    await deck.reload()
    #expect(source.state.withLock(\.seen) == [board.key])
    #expect(deck.top == gift)
    await deck.reload()
    #expect(source.state.withLock(\.seen) == [board.key])
}

@MainActor @Test func earlierComesAPageAtATimeAndFiltersToUnseen() async throws {
    let seenNote = card(.note, "39", minutes: -2880, text: "前天的话。").with(isSeen: true)
    let older = card(.board, "b0", minutes: -4320, text: "大前天的话。")
    let source = CardsInMemory(CoachPageCards(stack: [board], earlier: [oldNote, seenNote, older]))
    let deck = CoachDeck(squad: deckSquad, source: source)
    await deck.reload()
    #expect(deck.earlier.map(\.id) == ["40", "39"])
    #expect(deck.hasMoreEarlier)
    await deck.loadMoreEarlier()
    #expect(deck.earlier.map(\.id) == ["40", "39", "b0"])
    #expect(!deck.hasMoreEarlier)

    await deck.showEarlier(.unseen)
    #expect(deck.earlier.map(\.id) == ["40", "b0"])
    // Opened from 以前, a card is seen on every phone; it stays in the list until it is read again.
    deck.read(oldNote)
    #expect(deck.earlier.first?.isSeen == true)
    try await Task.sleep(for: .milliseconds(50))
    #expect(source.state.withLock(\.seen) == [oldNote.key])
    // A card swiped away now isn't one of the unseen.
    deck.seen(board)
    #expect(deck.earlier.map(\.id) == ["40", "b0"])
    await deck.showEarlier(.all)
    #expect(deck.earlier.first?.key == board.key)
}

@MainActor @Test func challengesListsEveryChallengeTheStacksToo() async {
    let today = card(.challenge, "41", minutes: 0, challenge: CoachPageCard.Challenge(title: "喝水"))
    let done = card(
        .challenge, "30", minutes: -1440,
        challenge: CoachPageCard.Challenge(title: "拉伸", answer: .accepted, completedBy: .member))
    let source = CardsInMemory(CoachPageCards(stack: [today], earlier: [oldNote, done]))
    let deck = CoachDeck(squad: deckSquad, source: source)
    await deck.reload()
    await deck.showEarlier(.challenges)
    #expect(deck.earlier.map(\.id) == ["41", "30"])
    #expect(deck.earlier.last?.challenge?.completedBy == .member)
    #expect(source.state.withLock(\.filters) == [.all, .challenges])
    // Swiping today's challenge away leaves the list as it is: it was in it already.
    deck.seen(today)
    #expect(deck.earlier.map(\.id) == ["41", "30"])
}

@MainActor @Test func aChallengeCardIsFoundByItsNoteHereOrInEarlier() async {
    // The morning note and its challenge share the note's id; only the challenge is wanted.
    let note = card(.note, "41", minutes: 0, text: "今天拉一拉。")
    let source = CardsInMemory(CoachPageCards(stack: [note], earlier: [oldNote, stretch.with(isSeen: true)]))
    let deck = CoachDeck(squad: deckSquad, source: source)
    // Before the page was ever read, 以前's challenges have it.
    #expect(await deck.challengeCard(note: "41")?.key == stretch.key)
    #expect(source.state.withLock(\.filters) == [.challenges])
    // Once read, the page's own copy, as it stands, without another read.
    await deck.reload()
    let read = source.state.withLock(\.filters).count
    #expect(await deck.challengeCard(note: "41")?.isSeen == true)
    #expect(source.state.withLock(\.filters).count == read)
    #expect(await deck.challengeCard(note: "99") == nil)
}
