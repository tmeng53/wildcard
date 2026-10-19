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
    private var lastWrite: Task<Result<Void, AccountError>, Never>?
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
        do {
            try await ensureRestored()
        } catch .storeFailed {
            // The stored session can't be read; saving the new one replaces it.
        }
        let new = try await provider.signIn(with: credential)
        // In memory first, so a renewal of the old session that finishes during the save sees
        // it was replaced and keeps nothing.
        session = new
        restored = true
        renewal = nil
        publish()
        do {
            try await persist()
        } catch {
            // Signed out, on the device too, rather than back on the old session, whose renewal
            // may already have used its refresh token.
            if session == new {
                session = nil
                publish()
                try? await persist()
            }
            try? await provider.signOut(new)
            throw error
        }
        return new.member
    }

    /// A current access token for our API. Pass `rejected` with the token the API just refused
    /// (it can refuse one before its expiry), and it is renewed unless it was already replaced.
    ///
    /// Throws `signedOut` when nobody is signed in or the session can't be renewed, `unavailable`
    /// when renewing needs the provider and it can't be reached, and `storeLocked` or
    /// `storeFailed` while the stored session can't be read yet.
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
        try await end(current)
    }

    /// Signs out as `signOut()` does, but only while `accessToken` is still the session's: for
    /// when the API refused it even after renewal. A session signed in since stays.
    public func signOut(ifCurrent accessToken: String) async throws(AccountError) {
        try await ensureRestored()
        guard let current = session, current.accessToken == accessToken else { return }
        try await end(current)
    }

    // MARK: - Private

    /// Ends `current`, which must be the session: on the device first, then at the provider.
    private func end(_ current: Session) async throws(AccountError) {
        session = nil
        renewal = nil
        publish()
        let cleared: Result<Void, AccountError>
        do {
            try await persist()
            cleared = .success(())
        } catch {
            cleared = .failure(error)
        }
        try? await provider.signOut(current)
        try cleared.get()
    }

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
        var unreadable = false
        do throws(AccountError) {
            stored = try await store.load()
        } catch let error where error == .storeLocked || error == .storeFailed {
            restoring = nil
            return error
        } catch {
            // Garbled, or written by a build that reads another version: sign in again.
            stored = nil
            unreadable = true
        }
        // Signed in while reading: the new session wins.
        if restored { return nil }
        session = stored
        restored = true
        publish()
        if unreadable { try? await persist() }
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
        guard let latest = session, latest.refreshToken == current.refreshToken else {
            if case .success(let orphan) = result { try? await provider.signOut(orphan) }
            return session == nil ? .failure(.signedOut) : .success(())
        }
        switch result {
        case .success(let new):
            session = new
            // If the save fails the member stays signed in until the app quits, and signs in
            // again at the next launch: the stored refresh token is already used up.
            try? await persist()
            return .success(())
        case .failure(.signedOut):
            session = nil
            publish()
            try? await persist()
            return .failure(.signedOut)
        case .failure(let error):
            return .failure(error)
        }
    }

    /// Writes the session in memory to the store, after any write already under way. Each write
    /// reads the session when its turn comes, so the store always ends on the latest one: a
    /// renewal's save can never land after a sign-out's clear.
    private func persist() async throws(AccountError) {
        let previous = lastWrite
        let write = Task { () -> Result<Void, AccountError> in
            _ = await previous?.value
            return await self.writeCurrent()
        }
        lastWrite = write
        try await write.value.get()
    }

    private func writeCurrent() async -> Result<Void, AccountError> {
        do throws(AccountError) {
            if let session {
                try await store.save(session)
            } else {
                try await store.clear()
            }
            return .success(())
        } catch {
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
