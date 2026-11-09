import Contracts
import Foundation
import Observation

/// How the coach page reaches the coach's cards. An adapter talks to the API; previews and UI
/// tests use one in memory.
public protocol CoachCardSource: Sendable {
    /// The member's stack (unseen, oldest first) and 以前 (newest first) in `squad`.
    func cards(in squad: SquadID) async throws(SquadError) -> CoachPageCards
    /// A page of 以前 in `squad`, newest first, from `cursor` (the page before's `next`, nil for
    /// the first); only the cards not seen yet when `unseenOnly`.
    func earlier(in squad: SquadID, from cursor: String?, unseenOnly: Bool) async throws(SquadError)
        -> CoachEarlierCards
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

    /// What 以前 lists (Tracy, 2026-11-09): every card, or only the ones not seen yet.
    public enum EarlierFilter: Hashable, Sendable, CaseIterable {
        case all, unseen
    }

    public private(set) var load: Load = .loading
    /// The cards still to see, the top one first.
    public private(set) var stack: [CoachPageCard] = []
    /// 以前: the pages read so far, newest first, a page at a time as the member scrolls.
    public private(set) var earlier: [CoachPageCard] = []
    public private(set) var earlierFilter: EarlierFilter = .all
    /// Whether 以前 has another page to read.
    public var hasMoreEarlier: Bool { earlierNext != nil }
    /// A page of 以前 is on its way.
    public private(set) var isLoadingEarlier = false
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
    /// Cards swiped away whose seen mark didn't reach the server yet; the next read sends them again.
    @ObservationIgnored private var unmarked: [CoachPageCard.Key] = []
    /// The cards swiped away on this page, newest first, which a read already on its way doesn't
    /// bring back into the stack.
    @ObservationIgnored private var swiped: [CoachPageCard] = []
    @ObservationIgnored private var earlierNext: String?

    /// `wear` puts a gift on the member's character (立刻穿上) once it is opened; `changed` is
    /// called after a gift is opened or a card seen, so 我's wardrobe and 今天 read again.
    public init(
        squad: SquadID, source: any CoachCardSource, wear: @escaping @MainActor (String) async -> Void = { _ in },
        changed: @escaping @MainActor () -> Void = {}
    ) {
        (self.squad, self.source, self.wear, self.changed) = (squad, source, wear, changed)
    }

    /// The card on top, or nil once everything is seen (「暂时没有新消息」).
    public var top: CoachPageCard? { stack.first }

    public func reload() async {
        var stillUnmarked: [CoachPageCard.Key] = []
        for key in unmarked {
            do { try await source.markSeen(key, in: squad) } catch { stillUnmarked.append(key) }
        }
        unmarked = stillUnmarked
        do {
            let cards = try await source.cards(in: squad)
            // A card swiped away while the read was on its way stays in 以前.
            let seenHere = Set(swiped.map(\.key))
            stack = cards.stack.filter { !seenHere.contains($0.key) }
            load = .loaded
        } catch {
            if load != .loaded { load = .failed(error) }
        }
        await readEarlier(from: nil)
    }

    /// 全部 or 未读: 以前 starts again from its newest card.
    public func showEarlier(_ filter: EarlierFilter) async {
        guard filter != earlierFilter else { return }
        earlierFilter = filter
        earlier = []
        earlierNext = nil
        await readEarlier(from: nil)
    }

    /// The next page of 以前, once the member scrolls near its end.
    public func loadMoreEarlier() async {
        guard let earlierNext else { return }
        await readEarlier(from: earlierNext)
    }

    /// A card opened from 以前 is seen, on every phone.
    public func read(_ card: CoachPageCard) {
        guard !current(card).isSeen else { return }
        replace(current(card).with(isSeen: true))
        Task {
            do { try await source.markSeen(card.key, in: squad) } catch { unmarked.append(card.key) }
        }
    }

    private func readEarlier(from cursor: String?) async {
        // A first page always goes (a filter may change while one is on its way); a next one waits.
        guard cursor == nil || !isLoadingEarlier else { return }
        isLoadingEarlier = true
        defer { isLoadingEarlier = false }
        let filter = earlierFilter
        guard let page = try? await source.earlier(in: squad, from: cursor, unseenOnly: filter == .unseen),
            filter == earlierFilter
        else { return }
        if cursor == nil {
            // What was swiped away here comes first, though the server may not have it yet.
            let fresh = Set(page.cards.map(\.key))
            let local = filter == .all ? swiped.filter { !fresh.contains($0.key) } : []
            earlier = (local + page.cards).sorted { $0.time > $1.time }
        } else {
            let known = Set(earlier.map(\.key))
            earlier += page.cards.filter { !known.contains($0.key) }
        }
        earlierNext = page.next
    }

    /// Swiped right: the card goes into 以前 at once and is marked seen on the server.
    public func seen(_ card: CoachPageCard) {
        guard let index = stack.firstIndex(where: { $0.key == card.key }) else { return }
        let gone = stack.remove(at: index).with(isSeen: true)
        swiped.insert(gone, at: 0)
        if earlierFilter == .all { earlier.insert(gone, at: 0) }
        putAway += 1
        if failed == card.key { failed = nil }
        Task {
            do {
                try await source.markSeen(gone.key, in: squad)
                if gone.kind == .note || gone.kind == .challenge { changed() }
            } catch {
                // It stays in 以前 here and is sent again on the next read, so other phones agree.
                unmarked.append(gone.key)
            }
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
        (stack + earlier + swiped).first { $0.key == card.key } ?? card
    }

    private func replace(_ card: CoachPageCard) {
        if let index = stack.firstIndex(where: { $0.key == card.key }) { stack[index] = card }
        if let index = earlier.firstIndex(where: { $0.key == card.key }) { earlier[index] = card }
        if let index = swiped.firstIndex(where: { $0.key == card.key }) { swiped[index] = card }
    }
}
