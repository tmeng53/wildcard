import Contracts
import Foundation

/// The server, as the home and 打卡 need it. The app passes the API adapter (`Backend`), or an
/// in-memory squad for previews and UI tests. Every call fails with a `CheckInError`; `.notSent`
/// means trying again later is safe.
public protocol CheckInBackend: Sendable {
    /// The home as last loaded, read from the device without the network; nil before the first
    /// load, or after signing out.
    func savedHome() async -> Home?
    /// Loads the home from the server and keeps a copy on the device. Nil when the member is in
    /// no squad yet.
    func home() async throws(CheckInError) -> Home?
    /// Uploads a photo for a check-in to list. Each upload is for one check-in only.
    func upload(_ photo: PreparedPhoto) async throws(CheckInError) -> PhotoRef
    /// Saves a check-in under its own id. Safe to retry: the same check-in again answers with
    /// the saved one.
    func save(_ checkIn: CheckIn) async throws(CheckInError) -> CheckIn
    func reactions(to checkIn: CheckInID) async throws(CheckInError) -> [Reaction]
    /// Sets the member's one reaction on a check-in, replacing any earlier one.
    func react(_ kind: ReactionKind, to checkIn: CheckInID) async throws(CheckInError)
    func removeReaction(from checkIn: CheckInID) async throws(CheckInError)
}

/// Check-ins waiting to go out, kept on the device so a post made offline survives the app
/// closing. The app passes a file-backed one (`Backend`); tests and previews keep it in memory.
public protocol Outbox: Sendable {
    func load() async -> [PendingCheckIn]
    /// Replaces what is kept with `pending`, oldest first.
    func save(_ pending: [PendingCheckIn]) async
}
