import AccountDomain
import Contracts
import Foundation
import Testing

// Switching an admin between their own account and their demo accounts.

private let demo = MemberID(UUID(uuid: (7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7)))
private let handOff = Credential.handOff(refreshToken: "handed-off")

private func admin(_ provider: FakeProvider, _ store: MemoryStore, kept: MemoryStore) -> AccountSession {
    AccountSession(provider: provider, store: store, kept: kept, now: { start })
}

@Test func switchingToADemoAccountKeepsTheOwnSessionForTheWayBack() async throws {
    let provider = FakeProvider()
    await provider.signInAs(session("demo", member: demo))
    let (store, kept) = (MemoryStore(session("own")), MemoryStore())
    let account = admin(provider, store, kept: kept)

    #expect(try await account.switchToDemo(with: handOff) == demo)
    #expect(await store.saved == session("demo", member: demo))
    #expect(await kept.saved == session("own"))
    #expect(await account.isOnDemo())

    #expect(try await account.returnFromDemo() == tracy)
    #expect(try await account.accessToken() == "access-own")
    #expect(await store.saved == session("own"))
    #expect(await kept.saved == nil)
    #expect(await !account.isOnDemo())
    // The demo session ends; the admin's own was never signed out.
    #expect(await provider.signedOut == [session("demo", member: demo)])
}

@Test func switchingOnFromADemoAccountKeepsTheFirstSessionAndEndsTheOneLeft() async throws {
    let provider = FakeProvider()
    let other = MemberID(UUID(uuid: (8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8)))
    let (store, kept) = (MemoryStore(session("own")), MemoryStore())
    let account = admin(provider, store, kept: kept)
    await provider.signInAs(session("demo", member: demo))
    try await account.switchToDemo(with: handOff)
    await provider.signInAs(session("other", member: other))

    #expect(try await account.switchToDemo(with: handOff) == other)
    #expect(await kept.saved == session("own"))
    #expect(await provider.signedOut == [session("demo", member: demo)])
}

@Test func aFailedSwitchStaysOnTheOwnAccountAndKeepsNothing() async throws {
    let provider = FakeProvider()
    await provider.failSignIn(with: .credentialRejected)
    let (store, kept) = (MemoryStore(session("own")), MemoryStore())
    let account = admin(provider, store, kept: kept)

    await #expect(throws: AccountError.credentialRejected) { try await account.switchToDemo(with: handOff) }
    #expect(try await account.accessToken() == "access-own")
    #expect(await kept.saved == nil)
    await #expect(throws: AccountError.signedOut) { try await account.returnFromDemo() }
}

@Test func signingOutOfADemoAccountEndsTheKeptSessionToo() async throws {
    let provider = FakeProvider()
    await provider.signInAs(session("demo", member: demo))
    let (store, kept) = (MemoryStore(session("own")), MemoryStore())
    let account = admin(provider, store, kept: kept)
    try await account.switchToDemo(with: handOff)

    try await account.signOut()
    #expect(try await account.restore() == .signedOut)
    #expect(await kept.saved == nil)
    #expect(await provider.signedOut == [session("own"), session("demo", member: demo)])
}

@Test func switchingWithoutAPlaceToKeepTheSessionIsRefused() async throws {
    let account = AccountSession(provider: FakeProvider(), store: MemoryStore(session("own")), now: { start })
    await #expect(throws: AccountError.storeFailed) { try await account.switchToDemo(with: handOff) }
    #expect(try await account.accessToken() == "access-own")
}
