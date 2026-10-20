/// Why the API didn't take this phone. Each case is something the caller can act on.
public enum NotificationsError: Error, Equatable, Sendable {
    /// Nobody is signed in any more. The phone is registered again on the next sign-in.
    case signedOut
    /// The API or the network can't be reached. The phone is registered again on the next
    /// launch, when iOS hands the token over again.
    case unavailable
}
