import Contracts
import Foundation
import Observation

/// How the coach page reaches the coach's cards. An adapter talks to the API; previews and UI
/// tests use one in memory.
public protocol CoachCardSource: Sendable {
    /// The member's stack (unseen, oldest first) and 以前 (newest first) in `squad`.
    func cards(in squad: SquadID) async throws(SquadError) -> CoachPageCards
    /// Marks a card seen, so it is in 以前 on every phone; a seen note is also put away on 今天.
    /// Safe to repeat.
    func markSeen(_ card: CoachPageCard.Key, in squad: SquadID) async throws(SquadError)
    /// 拆开: keeps that the member opened a gift and whether they put it on then. The first
    /// opening stands.
    func openGift(_ piece: String, worn: Bool) async throws(SquadError) -> CoachPageCard.Gift
    /// Accepts or declines a day's challenge, once; the first answer stands. A decline may carry
    /// the member's reason, which only the coach reads.
    func answerChallenge(
        _ note: String, in squad: SquadID, with answer: CoachChallengeAnswer, reason: String?
    ) async throws(SquadError) -> CoachChallengeAnswer
}

/// The coach page (Tracy, 2026-11-08): the coach's cards the member hasn't seen, one at a time in
/// time order, each swiped away into 以前; a gift opened and a challenge answered in place.
@MainActor @Observable
public final class CoachDeck {
    public enum Load: Hashable, Sendable {
        case loading
        case loaded
        case failed(SquadError)
    }

    public private(set) var load: Load = .loading
    /// The cards still to see, the top one first.
    public private(set) var stack: [CoachPageCard] = []
    /// 以前: the cards seen, newest first.
    public private(set) var earlier: [CoachPageCard] = []
    /// The cards whose 拆开 or answer is on its way; their buttons hold still.
    public private(set) var sending: Set<CoachPageCard.Key> = []
    /// The last 拆开 or answer didn't go through; the card says so until the next one.
    public private(set) var failed: CoachPageCard.Key?
    /// Bumps each time a card is swiped into 以前, for the clock's nudge.
    public private(set) var putAway = 0

    public let squad: SquadID
    @ObservationIgnored private let source: any CoachCardSource
    @ObservationIgnored private let wear: @MainActor (String) async -> Void
    @ObservationIgnored private let changed: @MainActor () -> Void

    /// `wear` puts a gift on the member's character (立刻穿上) once it is opened; `changed` is
    /// called after a gift is opened or a card seen, so 我's wardrobe and 今天 read again.
    public init(
        squad: SquadID, source: any CoachCardSource, wear: @escaping @MainActor (String) async -> Void = { _ in },
        changed: @escaping @MainActor () -> Void = {}
    ) {
        (self.squad, self.source, self.wear, self.changed) = (squad, source, wear, changed)
    }

    /// The card on top, or nil once everything is seen (「今天的都看过了。」).
    public var top: CoachPageCard? { stack.first }

    public func reload() async {
        do {
            let cards = try await source.cards(in: squad)
            // A card swiped away while the read was on its way stays in 以前.
            let seenHere = Set(earlier.map(\.key))
            stack = cards.stack.filter { !seenHere.contains($0.key) }
            earlier = cards.earlier + earlier.filter { seen in !cards.earlier.contains { $0.key == seen.key } }
            earlier.sort { $0.time > $1.time }
            load = .loaded
        } catch {
            if load != .loaded { load = .failed(error) }
        }
    }

    /// Swiped right: the card goes into 以前 at once and is marked seen on the server.
    public func seen(_ card: CoachPageCard) {
        guard let index = stack.firstIndex(where: { $0.key == card.key }) else { return }
        let gone = stack.remove(at: index)
        earlier.insert(gone, at: 0)
        putAway += 1
        if failed == card.key { failed = nil }
        Task {
            // Not kept, it shows in the stack again on the next read, which is no harm.
            try? await source.markSeen(gone.key, in: squad)
            if gone.kind == .note || gone.kind == .challenge { changed() }
        }
    }

    /// 拆开, then 立刻穿上 (`worn`) or 一会儿再说: true once it is opened. Put on, the member wears it.
    @discardableResult
    public func open(_ card: CoachPageCard, worn: Bool) async -> Bool {
        guard let gift = card.gift, !sending.contains(card.key) else { return false }
        sending.insert(card.key)
        defer { sending.remove(card.key) }
        do {
            let opened = try await source.openGift(gift.piece, worn: worn)
            failed = nil
            replace(card.with(gift: opened))
            if worn { await wear(gift.piece) }
            changed()
            return true
        } catch {
            failed = card.key
            return false
        }
    }

    /// 接受挑战, or 不接挑战 with what the member typed to tell the coach why (Tracy, 2026-11-08),
    /// sent only when there is something.
    public func answer(_ card: CoachPageCard, _ answer: CoachChallengeAnswer, reason typed: String = "") async {
        guard let challenge = card.challenge, challenge.answer == nil, !sending.contains(card.key) else { return }
        sending.insert(card.key)
        defer { sending.remove(card.key) }
        do {
            let standing = try await source.answerChallenge(
                card.id, in: squad, with: answer,
                reason: answer == .declined ? CoachChallengeAnswer.reason(typed) : nil)
            failed = nil
            replace(card.with(challenge: challenge.answered(standing)))
        } catch {
            failed = card.key
        }
    }

    /// The card as it stands now, wherever it is.
    public func current(_ card: CoachPageCard) -> CoachPageCard {
        (stack + earlier).first { $0.key == card.key } ?? card
    }

    private func replace(_ card: CoachPageCard) {
        if let index = stack.firstIndex(where: { $0.key == card.key }) { stack[index] = card }
        if let index = earlier.firstIndex(where: { $0.key == card.key }) { earlier[index] = card }
    }
}
