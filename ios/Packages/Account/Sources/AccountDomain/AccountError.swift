/// Why signing in, or staying signed in, failed. Each case is something the caller can act on.
public enum AccountError: Error, Equatable, Sendable {
    /// The member closed the Sign in with Apple sheet. Not a failure to show.
    case canceled
    /// The auth provider refused the credential (an Apple token it can't verify, a wrong
    /// test password). Ask the member to try again.
    case credentialRejected
    /// The session can't be renewed any more (revoked, or the refresh token expired), so the
    /// member is signed out and signs in again.
    case signedOut
    /// The provider or the network can't be reached. The session is kept; try again later.
    case unavailable
    /// The secure store on the device refused to save or read the session.
    case storeFailed
    /// Stored session JSON carries a `version` this build doesn't read.
    case unsupportedVersion(Int)
}
