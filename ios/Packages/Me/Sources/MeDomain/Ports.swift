/// How 我 reaches the member's account. An adapter talks to the API; previews and UI tests use
/// one in memory.
public protocol MeService: Sendable {
    func overview() async throws(MeError) -> MeOverview
    /// Saves the character after the member edits it in the character editor.
    func save(_ character: MeCharacter) async throws(MeError)
    func setDailyPush(_ isOn: Bool) async throws(MeError)
    /// Deletes the account and everything that is the member's, for good. Signing out on this phone
    /// is the app's to do after.
    func deleteAccount(_ confirmation: DeletionConfirmation) async throws(MeError)
}

/// How the member confirmed deleting their account. Someone who signs in with Apple confirms
/// with Apple again, so the API can revoke the app's Apple tokens with the fresh code.
public enum DeletionConfirmation: Hashable, Sendable {
    case apple(authorizationCode: String)
    /// Test members on local Supabase, who sign in with a password.
    case signedInSession
}

/// What can go wrong on 我, by what the member can do about it.
public enum MeError: Error, Hashable, Sendable {
    /// No connection, or the server is down: try again.
    case unavailable
    /// The session ended: sign in again.
    case signedOut
    /// Apple's confirmation was closed before it finished: nothing happened.
    case confirmationCanceled
    /// Apple didn't confirm (no code came back): try again.
    case confirmationFailed
    /// The server refused what was saved (such as a nickname it doesn't take).
    case rejected
}
