import Contracts
import Foundation
import SquadDomain
import Testing

// A coach message on the coach page: stars, a tap that turns the card, words sent as 意见反馈.
// The fake source keeps answers as the API does, the first of each part standing.

private func words(_ zhHans: String) -> CatalogNames {
    CatalogNames(simplifiedChinese: zhHans, english: zhHans, traditionalChinese: zhHans)
}

private let rate = CoachMessage.Button(id: "rate", label: words("好了"), tap: [.close])
private let more = CoachMessage.Button(id: "more", label: words("还有话说"), tap: [.next("more")])
private let send = CoachMessage.Button(
    id: "send", label: words("发送"), tap: [.feedback("idea"), .open("feed"), .close])

private let equinox = CoachPageCard(
    kind: .message, id: "equinox", coach: CoachSpeaker(id: "xiaohun", name: "毛头"), look: "xiaohun",
    time: Date(timeIntervalSince1970: 1_794_150_000),
    message: CoachMessage(cards: [
        CoachMessage.Card(
            path: "", line: words("周四去的 Equinox，打个分？"), stars: true, buttons: [rate, more],
            thanks: words("收到。")),
        CoachMessage.Card(path: "more", line: words("还想说什么？"), input: CoachMessage.Input(), buttons: [send]),
    ]))

private let squad = SquadID(UUID(uuidString: "5a000000-0000-4000-8000-0000000000c2") ?? UUID())

@MainActor private final class Outside {
    var opened: [String] = []
    var feedback: [MessageFeedback] = []
    var feedbackWorks = true
    var ids = 0
}

@MainActor private func deck(_ source: MessageAnswers, _ outside: Outside) async -> CoachDeck {
    let deck = CoachDeck(
        squad: squad, source: source, open: { outside.opened.append($0) },
        sendFeedback: { sent in
            outside.feedback.append(sent)
            return outside.feedbackWorks
        },
        newID: {
            outside.ids += 1
            return UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", outside.ids)) ?? UUID()
        })
    await deck.reload()
    return deck
}

@MainActor @Test func starsGivenStandAndAClosingTapShowsTheThanks() async throws {
    let source = MessageAnswers(equinox)
    let deck = await deck(source, Outside())
    let card = try #require(deck.top)
    await deck.give(4, on: card, at: "")
    await deck.give(2, on: card, at: "")
    #expect(deck.current(card).message?.answered[""]?.stars == 4)
    await deck.tap(rate, on: card, at: "")
    #expect(deck.current(card).message?.place == .closed(""))
    #expect(source.parts == [.init(path: "", part: .stars(4)), .init(path: "", part: .tap("rate"))])
}

@MainActor @Test func aFollowUpCardSendsItsWordsAsFeedbackThenOpensItsPlace() async throws {
    let source = MessageAnswers(equinox)
    let outside = Outside()
    let deck = await deck(source, outside)
    let card = try #require(deck.top)
    await deck.tap(more, on: card, at: "")
    #expect(deck.current(card).message?.place == .card("more"))
    // Nothing typed: 发送 waits.
    await deck.tap(send, on: card, at: "more", typed: "  ")
    #expect(outside.feedback.isEmpty)
    await deck.tap(send, on: card, at: "more", typed: "  人有点多 ")
    #expect(outside.feedback.map(\.text) == ["人有点多"])
    #expect(outside.feedback.map(\.kind) == ["idea"])
    #expect(outside.opened == ["feed"])
    #expect(deck.current(card).message?.place == .closed("more"))
    #expect(
        source.parts.suffix(2) == [.init(path: "more", part: .text("人有点多")), .init(path: "more", part: .tap("send"))])
}

@MainActor @Test func feedbackThatFailsKeepsTheCardAndIsNotSentTwice() async throws {
    let source = MessageAnswers(equinox)
    let outside = Outside()
    let deck = await deck(source, outside)
    let card = try #require(deck.top)
    await deck.tap(more, on: card, at: "")
    outside.feedbackWorks = false
    await deck.tap(send, on: card, at: "more", typed: "人有点多")
    #expect(deck.failed == card.key)
    #expect(deck.current(card).message?.place == .card("more"))
    #expect(outside.opened.isEmpty)
    // It went this time, but keeping the answer failed: tried again, the words aren't sent twice.
    outside.feedbackWorks = true
    source.down = true
    await deck.tap(send, on: card, at: "more", typed: "人有点多")
    #expect(deck.failed == card.key)
    source.down = false
    await deck.tap(send, on: card, at: "more", typed: "人有点多")
    #expect(deck.failed == nil)
    #expect(outside.feedback.count == 2)
    // Tried again, it is the same message, so the server keeps it once.
    #expect(Set(outside.feedback.map(\.id)).count == 1)
    #expect(deck.current(card).message?.place == .closed("more"))
}

@MainActor @Test func starsThatDontReachTheServerAreTakenBack() async throws {
    let source = MessageAnswers(equinox)
    source.down = true
    let deck = CoachDeck(squad: squad, source: source)
    source.down = false
    await deck.reload()
    let card = try #require(deck.top)
    source.down = true
    await deck.give(5, on: card, at: "")
    #expect(deck.current(card).message?.answered[""]?.stars == nil)
    #expect(deck.failed == card.key)
}

/// The coach's page with one message on it, keeping its answers as the API does.
@MainActor private final class MessageAnswers: CoachCardSource {
    struct Sent: Equatable {
        let path: String
        let part: CoachMessage.Part
    }

    private let card: CoachPageCard
    private var answered: [String: CoachMessage.Answered] = [:]
    var parts: [Sent] = []
    var down = false

    init(_ card: CoachPageCard) { self.card = card }

    nonisolated func cards(in squad: SquadID) async throws(SquadError) -> CoachPageCards {
        let (card, answered) = await (self.card, self.answered)
        return CoachPageCards(stack: [card.with(message: card.message?.with(answered: answered))], earlier: [])
    }

    nonisolated func earlier(in squad: SquadID, from cursor: String?, showing filter: CoachDeck.EarlierFilter)
        async throws(SquadError) -> CoachEarlierCards
    { CoachEarlierCards(cards: [], next: nil) }

    nonisolated func markSeen(_ card: CoachPageCard.Key, in squad: SquadID) async throws(SquadError) {}

    nonisolated func openGift(_ piece: String, worn: Bool) async throws(SquadError) -> CoachPageCard.Gift {
        throw .outdated
    }

    nonisolated func answerChallenge(
        _ note: String, in squad: SquadID, with answer: CoachChallengeAnswer, reason: String?
    ) async throws(SquadError) -> CoachChallengeAnswer { throw .outdated }

    nonisolated func answerMessage(
        _ message: String, in squad: SquadID, on path: String, _ part: CoachMessage.Part
    ) async throws(SquadError) -> [String: CoachMessage.Answered] {
        guard let kept = await keep(path, part) else { throw .unavailable }
        return kept
    }

    private func keep(_ path: String, _ part: CoachMessage.Part) -> [String: CoachMessage.Answered]? {
        if down { return nil }
        parts.append(Sent(path: path, part: part))
        let was = answered[path] ?? CoachMessage.Answered()
        answered[path] =
            switch part {
            case .tap(let button): CoachMessage.Answered(tap: was.tap ?? button, stars: was.stars, text: was.text)
            case .stars(let stars): CoachMessage.Answered(tap: was.tap, stars: was.stars ?? stars, text: was.text)
            case .text(let text): CoachMessage.Answered(tap: was.tap, stars: was.stars, text: was.text ?? text)
            }
        return answered
    }
}
