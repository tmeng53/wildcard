import AccountDomain
import Contracts
import Foundation
import Testing

private func account(
    _ provider: FakeProvider, _ store: MemoryStore, clock: TestClock = TestClock()
) -> AccountSession {
    AccountSession(provider: provider, store: store, now: { clock.now })
}

// MARK: - Restoring

@Test func aStoredSessionSignsTheMemberInAtLaunch() async throws {
    let provider = FakeProvider()
    let account = account(provider, MemoryStore(session("stored")))
    #expect(try await account.restore() == .signedIn(tracy))
    #expect(try await account.accessToken() == "access-stored")
    #expect(await provider.refreshed.isEmpty)
}

@Test func noStoredSessionMeansSignedOut() async throws {
    let account = account(FakeProvider(), MemoryStore())
    #expect(try await account.restore() == .signedOut)
    await #expect(throws: AccountError.signedOut) { try await account.accessToken() }
}

@Test func anUnreadableStoredSessionIsClearedAndSignsOut() async throws {
    let store = MemoryStore(session("stored"), failsToLoad: .unsupportedVersion(2))
    let account = account(FakeProvider(), store)
    #expect(try await account.restore() == .signedOut)
    #expect(await store.saved == nil)
}

@Test func aLockedStoreKeepsTheSessionUntilTheDeviceIsUnlocked() async throws {
    let store = MemoryStore(session("stored"), failsToLoad: .storeLocked)
    let account = account(FakeProvider(), store)

    await #expect(throws: AccountError.storeLocked) { try await account.restore() }
    await #expect(throws: AccountError.storeLocked) { try await account.accessToken() }
    #expect(await store.saved == session("stored"))
    await store.unlock()
    #expect(try await account.restore() == .signedIn(tracy))
    #expect(try await account.accessToken() == "access-stored")
}

@Test func aStoreThatRefusesTheReadKeepsTheSessionForTheNextTry() async throws {
    let store = MemoryStore(session("stored"), failsToLoad: .storeFailed)
    let account = account(FakeProvider(), store)

    await #expect(throws: AccountError.storeFailed) { try await account.restore() }
    #expect(await store.saved == session("stored"))
    await store.unlock()
    #expect(try await account.restore() == .signedIn(tracy))
}

@Test func signingInReplacesAStoredSessionTheStoreKeepsRefusingToRead() async throws {
    let store = MemoryStore(session("stored"), failsToLoad: .storeFailed)
    let account = account(FakeProvider(), store)

    await #expect(throws: AccountError.storeFailed) { try await account.restore() }
    try await account.signIn(with: .apple(identityToken: "apple", nonce: "nonce"))
    #expect(try await account.restore() == .signedIn(tracy))
    #expect(try await account.accessToken() == "access-signed-in")
    #expect(await store.saved == session("signed-in"))
}

@Test func aGarbledStoredSessionIsClearedAndSignsOut() async throws {
    let store = MemoryStore(session("stored"), failsToLoad: .storeCorrupted)
    let account = account(FakeProvider(), store)
    #expect(try await account.restore() == .signedOut)
    #expect(await store.saved == nil)
}

// MARK: - Renewing

@Test func aTokenCloseToExpiryIsRenewedAndTheNewSessionSaved() async throws {
    let clock = TestClock()
    let provider = FakeProvider(renewals: [.success(session("renewed", expiresIn: 7200))])
    let store = MemoryStore(session("stored", expiresIn: 3600))
    let account = account(provider, store, clock: clock)

    clock.advance(by: 3600 - 61)
    #expect(try await account.accessToken() == "access-stored")
    clock.advance(by: 1)
    #expect(try await account.accessToken() == "access-renewed")
    #expect(await provider.refreshed == ["refresh-stored"])
    #expect(await store.saved == session("renewed", expiresIn: 7200))
}

@Test func aSessionAnotherProcessRenewedIsTakenInsteadOfRenewingAgain() async throws {
    let provider = FakeProvider(renewals: [.success(session("renewed-again"))])
    let store = MemoryStore(session("stored", expiresIn: 0))
    let account = account(provider, store)
    _ = try await account.restore()

    // The push's view renewed the shared session while the app held the old one.
    try await store.save(session("renewed-elsewhere"))
    #expect(try await account.accessToken() == "access-renewed-elsewhere")
    #expect(await provider.refreshed.isEmpty)
}

@Test func anOlderStoredSessionIsNotTakenOverOurs() async throws {
    let provider = FakeProvider(renewals: [.success(session("renewed"))])
    let store = MemoryStore(session("stored", expiresIn: 0))
    let account = account(provider, store)
    _ = try await account.restore()

    // A save that failed left an older session in the store: ours is renewed as usual.
    try await store.save(session("older", expiresIn: -60))
    #expect(try await account.accessToken() == "access-renewed")
    #expect(await provider.refreshed == ["refresh-stored"])
}

@Test func callersAskingAtOnceShareOneRenewal() async throws {
    let provider = FakeProvider(renewals: [.success(session("renewed"))], gated: true)
    let account = account(provider, MemoryStore(session("stored", expiresIn: 0)))

    async let first = account.accessToken()
    async let second = account.accessToken()
    async let third = account.accessToken()
    while await provider.refreshesWaiting == 0 { await Task.yield() }
    // Give the other two callers every chance to start a second renewal.
    for _ in 0..<100 { await Task.yield() }
    await provider.release()

    #expect(try await [first, second, third] == ["access-renewed", "access-renewed", "access-renewed"])
    #expect(await provider.refreshed == ["refresh-stored"])
}

@Test func aSessionTheProviderWontRenewSignsOut() async throws {
    let provider = FakeProvider(renewals: [.failure(.signedOut)])
    let store = MemoryStore(session("stored", expiresIn: 0))
    let account = account(provider, store)

    await #expect(throws: AccountError.signedOut) { try await account.accessToken() }
    #expect(try await account.restore() == .signedOut)
    #expect(await store.saved == nil)
}

@Test func anUnreachableProviderKeepsTheSession() async throws {
    let provider = FakeProvider(renewals: [.failure(.unavailable), .success(session("renewed"))])
    let store = MemoryStore(session("stored", expiresIn: 0))
    let account = account(provider, store)

    await #expect(throws: AccountError.unavailable) { try await account.accessToken() }
    #expect(await store.saved == session("stored", expiresIn: 0))
    #expect(try await account.accessToken() == "access-renewed")
    #expect(await provider.refreshed == ["refresh-stored", "refresh-stored"])
}

@Test func aTokenTheApiRefusedIsRenewedOnce() async throws {
    let provider = FakeProvider(renewals: [.success(session("renewed"))])
    let account = account(provider, MemoryStore(session("stored")))

    #expect(try await account.accessToken(rejected: "access-stored") == "access-renewed")
    // A second caller that was refused the same old token gets the new one, with no renewal.
    #expect(try await account.accessToken(rejected: "access-stored") == "access-renewed")
    #expect(await provider.refreshed == ["refresh-stored"])
}

@Test func signingInDuringARenewalHandsOutTheNewSession() async throws {
    let provider = FakeProvider(renewals: [.success(session("renewed"))], gated: true)
    let store = MemoryStore(session("stored", expiresIn: 0))
    let account = account(provider, store)

    async let token = account.accessToken()
    while await provider.refreshesWaiting == 0 { await Task.yield() }
    try await account.signIn(with: .apple(identityToken: "apple", nonce: "nonce"))
    await provider.release()

    #expect(try await token == "access-signed-in")
    #expect(await store.saved == session("signed-in"))
}

@Test func aCallerJoiningARenewalGetsTheSessionThatReplacedIt() async throws {
    let provider = FakeProvider(renewals: [.success(session("renewed"))], gated: true)
    let account = account(provider, MemoryStore(session("stored", expiresIn: 0)))

    async let first = account.accessToken()
    while await provider.refreshesWaiting == 0 { await Task.yield() }
    async let second = account.accessToken()
    // Let the second caller reach the renewal before signing in.
    for _ in 0..<100 { await Task.yield() }
    try await account.signIn(with: .apple(identityToken: "apple", nonce: "nonce"))
    await provider.release()

    #expect(try await first == "access-signed-in")
    #expect(try await second == "access-signed-in")
    #expect(await provider.refreshed == ["refresh-stored"])
    // The old session's renewal is never used, so it is ended at the provider.
    #expect(await provider.signedOut == [session("renewed")])
}

// MARK: - Signing in and out

@Test func signingInSavesTheSession() async throws {
    let store = MemoryStore()
    let account = account(FakeProvider(), store)
    #expect(try await account.signIn(with: .apple(identityToken: "apple", nonce: "nonce")) == tracy)
    #expect(await store.saved == session("signed-in"))
    #expect(try await account.accessToken() == "access-signed-in")
}

@Test func aRejectedCredentialLeavesTheMemberSignedOut() async throws {
    let provider = FakeProvider()
    await provider.failSignIn(with: .credentialRejected)
    let store = MemoryStore()
    let account = account(provider, store)

    await #expect(throws: AccountError.credentialRejected) {
        try await account.signIn(with: .apple(identityToken: "apple", nonce: "nonce"))
    }
    #expect(try await account.restore() == .signedOut)
    #expect(await store.saved == nil)
}

@Test func signingOutClearsTheDeviceEvenWhenTheProviderIsUnreachable() async throws {
    let provider = FakeProvider()
    await provider.failSignOut()
    let store = MemoryStore(session("stored"))
    let account = account(provider, store)

    try await account.signOut()
    #expect(try await account.restore() == .signedOut)
    #expect(await store.saved == nil)
    #expect(await provider.signedOut == [session("stored")])
}

@Test func aRefusedTokenSignsOutOnlyTheSessionItBelongsTo() async throws {
    let provider = FakeProvider()
    let store = MemoryStore(session("stored"))
    let account = account(provider, store)
    _ = try await account.restore()

    // Signed in again since the API refused the old session's token: the new one stays.
    try await account.signIn(with: .apple(identityToken: "token", nonce: "nonce"))
    try await account.signOut(ifCurrent: "access-stored")
    #expect(try await account.restore() == .signedIn(tracy))
    #expect(try await account.accessToken() == "access-signed-in")

    try await account.signOut(ifCurrent: "access-signed-in")
    #expect(try await account.restore() == .signedOut)
    #expect(await store.saved == nil)
}

@Test func aSignInTheDeviceCantSaveLeavesTheMemberSignedOut() async throws {
    let store = MemoryStore(session("stored"))
    await store.failSaves()
    let account = account(FakeProvider(), store)

    await #expect(throws: AccountError.storeFailed) {
        try await account.signIn(with: .apple(identityToken: "apple", nonce: "nonce"))
    }
    #expect(try await account.restore() == .signedOut)
    // The next launch doesn't bring the old session back either.
    #expect(await store.saved == nil)
    #expect(try await AccountSession(provider: FakeProvider(), store: store, now: { start }).restore() == .signedOut)
}

@Test func signingOutDuringARenewalsSaveStaysSignedOutAfterRelaunch() async throws {
    let provider = FakeProvider(renewals: [.success(session("renewed"))])
    let store = MemoryStore(session("stored", expiresIn: 0))
    let account = account(provider, store)
    #expect(try await account.restore() == .signedIn(tracy))
    await store.gateSaves()

    let token = Task { try await account.accessToken() }
    while await store.savesWaiting == 0 { await Task.yield() }
    let signOut = Task { try await account.signOut() }
    for _ in 0..<100 { await Task.yield() }
    await store.releaseSaves()

    // Signed out before the renewal finished, so its caller gets no token.
    await #expect(throws: AccountError.signedOut) { try await token.value }
    try await signOut.value
    #expect(await store.saved == nil)
    #expect(try await AccountSession(provider: provider, store: store, now: { start }).restore() == .signedOut)
}

@Test func aSignInTheDeviceCantSaveDuringARenewalLeavesTheMemberSignedOut() async throws {
    let provider = FakeProvider(renewals: [.success(session("renewed"))], gated: true)
    let store = MemoryStore(session("stored", expiresIn: 0))
    let account = account(provider, store)

    let token = Task { try await account.accessToken() }
    while await provider.refreshesWaiting == 0 { await Task.yield() }
    await store.failSaves()
    await #expect(throws: AccountError.storeFailed) {
        try await account.signIn(with: .apple(identityToken: "apple", nonce: "nonce"))
    }
    await provider.release()

    await #expect(throws: AccountError.signedOut) { try await token.value }
    await #expect(throws: AccountError.signedOut) { try await account.accessToken() }
    // The old refresh token is never sent twice, and both unused sessions are ended.
    #expect(await provider.refreshed == ["refresh-stored"])
    #expect(await provider.signedOut == [session("signed-in"), session("renewed")])
}

@Test func signingOutStillEndsTheProviderSessionWhenTheStoreFails() async throws {
    let provider = FakeProvider()
    let store = MemoryStore(session("stored"))
    await store.failClears()
    let account = account(provider, store)

    await #expect(throws: AccountError.storeFailed) { try await account.signOut() }
    #expect(await provider.signedOut == [session("stored")])
    #expect(try await account.restore() == .signedOut)
}

@Test func observersSeeEachChange() async throws {
    let account = account(FakeProvider(), MemoryStore())
    var states = await account.states().makeAsyncIterator()

    #expect(await states.next() == .signedOut)
    try await account.signIn(with: .apple(identityToken: "apple", nonce: "nonce"))
    #expect(await states.next() == .signedIn(tracy))
    try await account.signOut()
    #expect(await states.next() == .signedOut)
}
