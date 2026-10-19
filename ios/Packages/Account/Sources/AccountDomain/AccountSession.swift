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
    private var restoring: Task<Void, Never>?
    private var renewal: Task<Result<Session, AccountError>, Never>?
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

    /// Who is signed in, once the stored session has been read.
    public func restore() async -> AccountState {
        await ensureRestored()
        return state
    }

    /// The state now and each change after it, starting once the stored session has been read.
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
            Task { await ensureRestored() }
        }
        return stream
    }

    /// Signs in, replacing any session on the device.
    @discardableResult
    public func signIn(with credential: Credential) async throws(AccountError) -> MemberID {
        await ensureRestored()
        let new = try await provider.signIn(with: credential)
        try await store.save(new)
        session = new
        renewal = nil
        publish()
        return new.member
    }

    /// A current access token for our API. Pass `rejected` with the token the API just refused
    /// (it can refuse one before its expiry), and it is renewed unless it was already replaced.
    ///
    /// Throws `signedOut` when nobody is signed in or the session can't be renewed, and
    /// `unavailable` when renewing needs the provider and it can't be reached.
    public func accessToken(rejected: String? = nil) async throws(AccountError) -> String {
        await ensureRestored()
        guard let current = session else { throw .signedOut }
        let expiring = current.expiresAt.timeIntervalSince(now()) <= renewalMargin
        guard expiring || rejected == current.accessToken else { return current.accessToken }
        return try await renew(current).accessToken
    }

    /// Signs out on this device, then at the provider. The device is signed out even when the
    /// provider can't be reached. Throws `storeFailed` when the stored session can't be removed.
    public func signOut() async throws(AccountError) {
        await ensureRestored()
        guard let current = session else { return }
        session = nil
        renewal = nil
        publish()
        try await store.clear()
        try? await provider.signOut(current)
    }

    // MARK: - Private

    private var state: AccountState {
        session.map { .signedIn($0.member) } ?? .signedOut
    }

    private func ensureRestored() async {
        if restored { return }
        if let restoring {
            await restoring.value
            return
        }
        let task = Task { await loadStored() }
        restoring = task
        await task.value
    }

    private func loadStored() async {
        let stored: Session?
        do {
            stored = try await store.load()
        } catch {
            // Unreadable, or written by a build that reads another version: sign in again.
            stored = nil
            try? await store.clear()
        }
        session = stored
        restored = true
        publish()
    }

    private func renew(_ current: Session) async throws(AccountError) -> Session {
        if let renewal {
            return try await renewal.value.get()
        }
        let task = Task { [provider] () -> Result<Session, AccountError> in
            do throws(AccountError) {
                return .success(try await provider.refresh(current.refreshToken))
            } catch {
                return .failure(error)
            }
        }
        renewal = task
        let result = await task.value
        if renewal == task { renewal = nil }
        // Signed out, or signed in again, while renewing: the result belongs to an old session.
        guard session?.refreshToken == current.refreshToken else { throw .signedOut }
        switch result {
        case .success(let new):
            session = new
            // If the save fails the member stays signed in until the app quits, and signs in
            // again at the next launch: the stored refresh token is already used up.
            try? await store.save(new)
            return new
        case .failure(.signedOut):
            session = nil
            publish()
            try? await store.clear()
            throw .signedOut
        case .failure(let error):
            throw error
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
