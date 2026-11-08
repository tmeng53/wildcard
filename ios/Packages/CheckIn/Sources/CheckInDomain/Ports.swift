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
    /// Saves the phone's time zone on the member's profile when it is another one, so their day
    /// follows the phone's clock; true when it changed. The server checks a post's day against
    /// the profile's zone, so call it only once nothing is waiting in the outbox.
    func followPhoneZone() async throws(CheckInError) -> Bool
    /// Uploads a photo for a check-in to list. Each upload is for one check-in only.
    func upload(_ photo: PreparedPhoto) async throws(CheckInError) -> PhotoRef
    /// Saves a check-in under its own id. Safe to retry: the same check-in again answers with
    /// the saved one.
    func save(_ checkIn: CheckIn) async throws(CheckInError) -> CheckIn
    /// Makes the member's own saved check-in this one: its fields and photos, already uploaded.
    /// The same edit again changes nothing.
    func edit(_ checkIn: CheckIn) async throws(CheckInError) -> CheckIn
    /// Deletes the member's own check-in, with its photos and what teammates left on it; fine
    /// when it is gone already.
    func delete(_ checkIn: CheckInID) async throws(CheckInError)
    func reactions(to checkIn: CheckInID) async throws(CheckInError) -> [Reaction]
    /// Sets the member's one reaction on a check-in, replacing any earlier one.
    func react(_ emoji: Emoji, to checkIn: CheckInID) async throws(CheckInError)
    func removeReaction(from checkIn: CheckInID) async throws(CheckInError)
    /// Whom the member patted today in `squad` (拍一拍) and who patted them in the last day.
    func pokes(in squad: SquadID) async throws(CheckInError) -> SquadPokes
    /// Pats a teammate. Once a day each: patting them again the same day changes nothing.
    func pat(_ member: MemberID, in squad: SquadID) async throws(CheckInError)
    /// The coach the squad hired, standing on the home's sideline, with its newest 战术板 line;
    /// nil while the squad has none.
    func coach(in squad: SquadID) async throws(CheckInError) -> SidelineCoach?
    /// The coaches' morning notes (便条) waiting for the member on 今天, one at most from each of
    /// `squads`, in their order.
    func coachNotes(in squads: [SquadID]) async throws(CheckInError) -> [CoachMemberNote]
    /// The challenge in the member's morning note today in `squad`, answered or not; nil when
    /// there is none.
    func todayChallenge(in squad: SquadID) async throws(CheckInError) -> DayChallenge?
    /// 我完成了: marks a challenge done on its own day; the first completion stands, whoever made
    /// it, and is what comes back.
    func completeChallenge(_ note: String, in squad: SquadID) async throws(CheckInError) -> CoachChallengeCompleter
}

/// Check-ins waiting to go out, kept on the device so a post made offline survives the app
/// closing. The app passes a file-backed one (`Backend`); tests and previews keep it in memory.
public protocol Outbox: Sendable {
    func load() async -> [PendingCheckIn]
    /// Replaces what is kept with `pending`, oldest first.
    func save(_ pending: [PendingCheckIn]) async
}

/// The stores and props the member unlocked by training, and which of them this phone has
/// already told the member about, so each one is told once. The app passes one over our API that
/// keeps what was told in the member's folder (`Backend`).
public protocol UnlockLedger: Sendable {
    /// Every unlock the member has, the earliest first.
    func unlocks() async throws(CheckInError) -> [Unlock]
    /// What this phone has told, by `UnlockNews.key`; nil when it never looked.
    func told() async -> Set<String>?
    func keep(told: Set<String>) async
}
