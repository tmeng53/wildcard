import AccountDomain
import Contracts
import Foundation
import Synchronization

let tracy = MemberID(UUID(uuid: (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16)))
/// Someone else who signs in on the same device.
let sam = MemberID(UUID(uuid: (9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9)))
let start = Date(timeIntervalSince1970: 1_792_368_000)  // 2026-10-19T00:00:00Z

func session(_ name: String, expiresIn seconds: TimeInterval = 3600, member: MemberID = tracy) -> Session {
    Session(
        member: member, accessToken: "access-\(name)", refreshToken: "refresh-\(name)",
        expiresAt: start.addingTimeInterval(seconds))
}

/// A clock the test moves by hand.
final class TestClock: Sendable {
    private let seconds = Mutex(0.0)
    var now: Date { start.addingTimeInterval(seconds.withLock { $0 }) }
    func advance(by delta: TimeInterval) { seconds.withLock { $0 += delta } }
}

/// The secure store, in memory.
actor MemoryStore: SessionStore {
    var saved: Session?
    var failsToLoad: AccountError?

    init(_ saved: Session? = nil, failsToLoad: AccountError? = nil) {
        self.saved = saved
        self.failsToLoad = failsToLoad
    }

    func load() async throws(AccountError) -> Session? {
        if let failsToLoad { throw failsToLoad }
        return saved
    }

    private var savesFail = false
    private var clearsFail = false

    private var savesGated = false
    private var waitingSaves: [CheckedContinuation<Void, Never>] = []

    func save(_ session: Session) async throws(AccountError) {
        if savesFail { throw .storeFailed }
        if savesGated { await withCheckedContinuation { waitingSaves.append($0) } }
        saved = session
    }

    func clear() async throws(AccountError) {
        if clearsFail { throw .storeFailed }
        saved = nil
        failsToLoad = nil
    }

    /// The device's first unlock since it restarted.
    func unlock() { failsToLoad = nil }
    func failSaves() { savesFail = true }
    func failClears() { clearsFail = true }
    /// Holds each save until `releaseSaves()`, like a slow Keychain write.
    func gateSaves() { savesGated = true }
    func releaseSaves() {
        savesGated = false
        for continuation in waitingSaves { continuation.resume() }
        waitingSaves = []
    }
    var savesWaiting: Int { waitingSaves.count }
}

/// The auth provider. Each refresh answers with the next entry of `renewals`; with `gated`, a
/// refresh waits until the test calls `release()`, so callers can pile up behind it.
actor FakeProvider: AuthProvider {
    private var renewals: [Result<Session, AccountError>]
    private let gated: Bool
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private(set) var refreshed: [String] = []
    private(set) var signedOut: [Session] = []
    var signInResult: Result<Session, AccountError> = .success(session("signed-in"))
    var signOutFails = false

    init(renewals: [Result<Session, AccountError>] = [], gated: Bool = false) {
        self.renewals = renewals
        self.gated = gated
    }

    func signIn(with credential: Credential) async throws(AccountError) -> Session {
        try signInResult.get()
    }

    func refresh(_ refreshToken: String) async throws(AccountError) -> Session {
        refreshed.append(refreshToken)
        if gated { await withCheckedContinuation { waiting.append($0) } }
        guard !renewals.isEmpty else { throw .unavailable }
        return try renewals.removeFirst().get()
    }

    func signOut(_ session: Session) async throws(AccountError) {
        signedOut.append(session)
        if signOutFails { throw .unavailable }
    }

    func release() {
        for continuation in waiting { continuation.resume() }
        waiting = []
    }

    var refreshesWaiting: Int { waiting.count }

    func failSignIn(with error: AccountError) { signInResult = .failure(error) }
    func signInAs(_ session: Session) { signInResult = .success(session) }
    func failSignOut() { signOutFails = true }
}
