import CheckInDomain
import Contracts
import Foundation
import Testing

private func unlock(_ kind: Unlock.Kind, _ id: String, at seconds: TimeInterval) -> Unlock {
    Unlock(
        kind: kind, id: id, unlockedAt: Date(timeIntervalSince1970: seconds), sports: ["tennis"],
        checkIns: kind == .store ? 3 : 1)
}

actor ScriptedLedger: UnlockLedger {
    var server: [Unlock] = []
    var kept: Set<String>?
    var failing = false
    /// While set, each read waits until `release()`.
    private var held: [CheckedContinuation<Void, Never>]?

    init(told: Set<String>? = nil) { kept = told }

    func hold() { held = [] }
    func release() {
        let waiting = held ?? []
        held = nil
        for reader in waiting { reader.resume() }
    }
    /// Lets the oldest waiting read answer; later reads still wait.
    func releaseFirst() {
        guard var waiting = held, !waiting.isEmpty else { return }
        waiting.removeFirst().resume()
        held = waiting
    }
    var waiting: Int { held?.count ?? 0 }

    func set(server unlocks: [Unlock]) { server = unlocks }
    func set(failing: Bool) { self.failing = failing }

    func unlocks() async throws(CheckInError) -> [Unlock] {
        if held != nil { await withCheckedContinuation { held?.append($0) } }
        if failing { throw .notSent }
        return server
    }

    func told() async -> Set<String>? { kept }
    func keep(told: Set<String>) async { kept = told }
}

/// Lets a check the store started by itself finish.
@MainActor private func settle() async {
    for _ in 0..<50 { await Task.yield() }
}

@MainActor @Test func twoChecksAtOnceTellAnUnlockOnceEvenWhenTheFirstIsTakenBetween() async {
    let ledger = ScriptedLedger(told: [])
    let today = store(ScriptedBackend(), unlocks: ledger)
    await today.load()
    await ledger.set(server: [unlock(.store, "halfmoon", at: 1)])

    await ledger.hold()
    let first = Task { await today.checkUnlocks() }
    let second = Task { await today.checkUnlocks() }
    while await ledger.waiting == 0 { await Task.yield() }
    await settle()
    await ledger.releaseFirst()
    await first.value
    // The home tells the first check's news while the second is still to answer.
    #expect(today.takeUnlocks().map(\.id) == ["halfmoon"])
    await ledger.release()
    await second.value
    #expect(today.unlocked.isEmpty)
}

@Test func aPhoneThatNeverLookedTellsNothingAndTakesEverythingAsTold() {
    let news = UnlockNews.untold([unlock(.store, "deuce", at: 2), unlock(.prop, "racket", at: 1)], told: nil)
    #expect(news.tell.isEmpty)
    #expect(news.told == ["store/deuce", "prop/racket"])
}

@Test func tellsOnlyWhatThePhoneHasNotToldTheEarliestFirst() {
    let news = UnlockNews.untold(
        [unlock(.store, "deuce", at: 3), unlock(.prop, "racket", at: 1), unlock(.store, "halfmoon", at: 2)],
        told: ["prop/racket"])
    #expect(news.tell.map(\.id) == ["halfmoon", "deuce"])
    #expect(news.told == ["prop/racket", "store/halfmoon", "store/deuce"])
}

@Test func aStoreAndAPropWithOneIdAreToldApart() {
    let news = UnlockNews.untold([unlock(.prop, "deuce", at: 1)], told: ["store/deuce"])
    #expect(news.tell.map(UnlockNews.key) == ["prop/deuce"])
}

@MainActor @Test func aTrainingThatOpensAStoreQueuesItOnce() async throws {
    let ledger = ScriptedLedger()
    await ledger.set(server: [unlock(.prop, "racket", at: 1)])
    let today = store(ScriptedBackend(), unlocks: ledger)

    // The first load takes what the member already has as told.
    await today.load()
    #expect(today.unlocked.isEmpty)
    #expect(await ledger.kept == ["prop/racket"])

    await ledger.set(server: [unlock(.prop, "racket", at: 1), unlock(.store, "deuce", at: 2)])
    try await today.post(.trained(.sport("tennis"), nil, PostBody(photos: [], caption: "")))
    // The post returns before the check answers, so the payoff never waits for it.
    await settle()
    #expect(today.unlocked.map(\.id) == ["deuce"])
    #expect(today.takeUnlocks().map(\.id) == ["deuce"])
    #expect(today.unlocked.isEmpty)

    await today.load()
    #expect(today.unlocked.isEmpty)
}

@MainActor @Test func onlyATrainingLooksForUnlocks() async throws {
    let ledger = ScriptedLedger(told: [])
    let today = store(ScriptedBackend(), unlocks: ledger)
    await today.load()

    await ledger.set(server: [unlock(.store, "halfmoon", at: 1)])
    try await today.post(.disclaimer(try Disclaimer("累")))
    await settle()
    #expect(today.unlocked.isEmpty)

    await today.load()
    #expect(today.unlocked.map(\.id) == ["halfmoon"])
}

@MainActor @Test func offlineItTellsNothingAndKeepsNothing() async throws {
    let ledger = ScriptedLedger(told: [])
    await ledger.set(server: [unlock(.store, "halfmoon", at: 1)])
    await ledger.set(failing: true)
    let today = store(ScriptedBackend(), unlocks: ledger)
    await today.load()
    #expect(today.unlocked.isEmpty)
    #expect(await ledger.kept == [])

    await ledger.set(failing: false)
    await today.load()
    #expect(today.unlocked.map(\.id) == ["halfmoon"])
}
