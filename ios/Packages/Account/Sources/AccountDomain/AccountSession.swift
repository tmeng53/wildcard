import Contracts
import Foundation

/// Whether someone is signed in on this device.
public enum AccountState: Hashable, Sendable {
    case signedOut
    case signedIn(MemberID)
}

/// The member's sign-in on this device: signs in with a credential, keeps the session in the
/// secure store, hands out a current access token and signs out.
///
/// An access token lives about an hour. `accessToken()` renews it shortly before it expires,
/// and when many callers ask at once they share one renewal: the provider's refresh tokens are
/// single-use, so two renewals with the same one would sign the member out.
public actor AccountSession {
    private let provider: any AuthProvider
    private let store: any SessionStore
    private let now: @Sendable () -> Date
    private let renewalMargin: TimeInterval

    private var session: Session?
    private var restored = false
    private var restoring: Task<AccountError?, Never>?
    private var renewal: Task<Result<Void, AccountError>, Never>?
    private var observers: [Int: AsyncStream<AccountState>.Continuation] = [:]
    private var nextObserver = 0

    /// - Parameter renewalMargin: how long before it expires an access token is renewed, so a
    ///   request sent with it doesn't arrive just after.
    public init(
        provider: any AuthProvider, store: any SessionStore, now: @escaping @Sendable () -> Date,
        renewalMargin: TimeInterval = 60
    ) {
        self.provider = provider
        self.store = store
        self.now = now
        self.renewalMargin = renewalMargin
    }

    /// Who is signed in, once the stored session has been read. Throws `storeLocked` while the
    /// device hasn't been unlocked since it restarted; ask again once it has.
    public func restore() async throws(AccountError) -> AccountState {
        try await ensureRestored()
        return state
    }

    /// The state now and each change after it, starting once the stored session has been read
    /// (while the store is locked, once a later call reads it).
    public func states() -> AsyncStream<AccountState> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: AccountState.self, bufferingPolicy: .bufferingNewest(1))
        let key = nextObserver
        nextObserver += 1
        observers[key] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeObserver(key) }
        }
        if restored {
            continuation.yield(state)
        } else {
            Task { try? await ensureRestored() }
        }
        return stream
    }

    /// Signs in, replacing any session on the device.
    @discardableResult
    public func signIn(with credential: Credential) async throws(AccountError) -> MemberID {
        try await ensureRestored()
        let new = try await provider.signIn(with: credential)
        // In memory first, so a renewal of the old session that finishes during the save sees
        // it was replaced and saves nothing.
        let previous = session
        session = new
        renewal = nil
        publish()
        do {
            try await store.save(new)
        } catch {
            if session == new {
                session = previous
                publish()
            }
            throw error
        }
        return new.member
    }

    /// A current access token for our API. Pass `rejected` with the token the API just refused
    /// (it can refuse one before its expiry), and it is renewed unless it was already replaced.
    ///
    /// Throws `signedOut` when nobody is signed in or the session can't be renewed, and
    /// `unavailable` when renewing needs the provider and it can't be reached.
    public func accessToken(rejected: String? = nil) async throws(AccountError) -> String {
        try await ensureRestored()
        guard let current = session else { throw .signedOut }
        let expiring = current.expiresAt.timeIntervalSince(now()) <= renewalMargin
        guard expiring || rejected == current.accessToken else { return current.accessToken }
        return try await renew(current).accessToken
    }

    /// Signs out on this device and at the provider. The device is signed out even when the
    /// provider can't be reached, and the provider is told even when the stored session can't be
    /// removed (which then throws `storeFailed`), so its refresh token stops working either way.
    public func signOut() async throws(AccountError) {
        try await ensureRestored()
        guard let current = session else { return }
        session = nil
        renewal = nil
        publish()
        let cleared: Result<Void, AccountError>
        do {
            try await store.clear()
            cleared = .success(())
        } catch {
            cleared = .failure(error)
        }
        try? await provider.signOut(current)
        try cleared.get()
    }

    // MARK: - Private

    private var state: AccountState {
        session.map { .signedIn($0.member) } ?? .signedOut
    }

    private func ensureRestored() async throws(AccountError) {
        if restored { return }
        let task: Task<AccountError?, Never>
        if let restoring {
            task = restoring
        } else {
            task = Task { await loadStored() }
            restoring = task
        }
        if let error = await task.value { throw error }
    }

    /// Reads the stored session once. While the store is locked or refuses the read, returns
    /// that error and leaves the next call to read it again: the session is still there, and
    /// must not be cleared.
    private func loadStored() async -> AccountError? {
        let stored: Session?
        do throws(AccountError) {
            stored = try await store.load()
        } catch let error where error == .storeLocked || error == .storeFailed {
            restoring = nil
            return error
        } catch {
            // Garbled, or written by a build that reads another version: sign in again.
            stored = nil
            try? await store.clear()
        }
        session = stored
        restored = true
        publish()
        return nil
    }

    /// Renews `current`, or joins the renewal already running, and returns the session to use
    /// now: the renewed one, or the one that replaced it if the member signed in again meanwhile.
    private func renew(_ current: Session) async throws(AccountError) -> Session {
        let task: Task<Result<Void, AccountError>, Never>
        if let renewal {
            task = renewal
        } else {
            task = Task { await refreshAndKeep(current) }
            renewal = task
        }
        let result = await task.value
        if renewal == task { renewal = nil }
        try result.get()
        // Read after the wait, so every caller gets the latest session, never an old one.
        guard let latest = session else { throw .signedOut }
        return latest
    }

    private func refreshAndKeep(_ current: Session) async -> Result<Void, AccountError> {
        let result: Result<Session, AccountError>
        do throws(AccountError) {
            result = .success(try await provider.refresh(current.refreshToken))
        } catch {
            result = .failure(error)
        }
        // Signed out, or signed in again, while renewing: the result belongs to an old session.
        guard let latest = session else { return .failure(.signedOut) }
        guard latest.refreshToken == current.refreshToken else {
            if case .success(let orphan) = result { try? await provider.signOut(orphan) }
            return .success(())
        }
        switch result {
        case .success(let new):
            session = new
            // If the save fails the member stays signed in until the app quits, and signs in
            // again at the next launch: the stored refresh token is already used up.
            try? await store.save(new)
            return .success(())
        case .failure(.signedOut):
            session = nil
            publish()
            try? await store.clear()
            return .failure(.signedOut)
        case .failure(let error):
            return .failure(error)
        }
    }

    private func publish() {
        let current = state
        for continuation in observers.values { continuation.yield(current) }
    }

    private func removeObserver(_ key: Int) {
        observers[key] = nil
    }
}
