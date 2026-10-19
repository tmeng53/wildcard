import Foundation

/// What the member signs in with.
public enum Credential: Sendable, Equatable {
    /// Sign in with Apple's identity token, and the raw nonce whose SHA-256 the request carried.
    case apple(identityToken: String, nonce: String)
    #if DEBUG
    /// A test member on local Supabase, for the simulator and UI tests, which can't do a real
    /// Sign in with Apple. Never compiled into a release build.
    case testMember(email: String, password: String)
    #endif
}

/// The auth provider, written without naming one. Supabase Auth is the adapter today; changing
/// provider means a new adapter, not a change to the session.
public protocol AuthProvider: Sendable {
    /// Exchanges a credential for a new session. Throws `credentialRejected` or `unavailable`.
    func signIn(with credential: Credential) async throws(AccountError) -> Session
    /// A new session for a refresh token. Throws `signedOut` when the provider won't renew it,
    /// `unavailable` when it can't be asked.
    func refresh(_ refreshToken: String) async throws(AccountError) -> Session
    /// Ends the session at the provider, so its refresh token stops working.
    func signOut(_ session: Session) async throws(AccountError)
}

/// Where the session is kept between launches. The app's adapter is the Keychain.
public protocol SessionStore: Sendable {
    func load() async throws(AccountError) -> Session?
    func save(_ session: Session) async throws(AccountError)
    func clear() async throws(AccountError)
}
