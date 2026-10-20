/// Why the story couldn't be read. Each case is something the caller can act on.
public enum RecapError: Error, Equatable, Sendable {
    /// Nobody is signed in any more.
    case signedOut
    /// The reader isn't in the squad (any more).
    case notInSquad
    /// The API or the network can't be reached; trying again later is safe.
    case unavailable
}
