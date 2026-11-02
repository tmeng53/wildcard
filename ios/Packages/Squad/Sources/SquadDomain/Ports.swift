import Contracts
import Foundation

/// Everything 小队设置 shows, read together.
public struct SquadSettings: Hashable, Sendable {
    public var squad: Squad
    /// The signed-in member.
    public let viewer: MemberID
    /// Each member's nickname and character; a member who hasn't made theirs yet is missing.
    public var characters: [MemberID: MemberCharacter]
    public var scene: SquadScene
    public var coach: SquadCoach
    /// The member's day and clock when the page was read, for 「执教第 N 周」.
    public let today: LocalDay
    public let timeZone: TimeZone

    public init(
        squad: Squad, viewer: MemberID, characters: [MemberID: MemberCharacter], scene: SquadScene,
        coach: SquadCoach, today: LocalDay, timeZone: TimeZone
    ) {
        self.squad = squad
        self.viewer = viewer
        self.characters = characters
        self.scene = scene
        self.coach = coach
        self.today = today
        self.timeZone = timeZone
    }
}

/// How 小队设置 reaches the squad. An adapter talks to the API; previews and UI tests use one in
/// memory.
public protocol SquadSettingsService: Sendable {
    /// The member's squad (the app shows the earliest joined), with its members and scene.
    func settings() async throws(SquadError) -> SquadSettings
    func rename(_ squad: SquadID, to name: SquadName) async throws(SquadError) -> Squad
    func handCaptaincy(of squad: SquadID, to member: MemberID) async throws(SquadError) -> Squad
    /// Takes a member out: the member themselves (leaving), or anyone, for the captain.
    func remove(_ member: MemberID, from squad: SquadID) async throws(SquadError)
    /// Picks the scene for the week open now, once.
    func pick(_ scene: SceneID, for squad: SquadID, week: LocalDay) async throws(SquadError) -> SquadScene
    /// The coaches a squad can hire now (教练市场).
    func coaches() async throws(SquadError) -> [Coach]
    /// Hires `coach` for the squad, firing its other coach first in the same step (换教练).
    /// Only the captain may; asking again for the coach it has answers as before.
    func hire(_ coach: CoachID, for squad: SquadID) async throws(SquadError) -> SquadCoach
    /// Fires the squad's coach; only the captain may. Its memory stays with the squad.
    func fireCoach(of squad: SquadID) async throws(SquadError) -> SquadCoach
}

/// What can go wrong on 小队设置, by what the member can do about it.
public enum SquadError: Error, Hashable, Sendable {
    /// No connection, or the server is down: try again.
    case unavailable
    /// The session ended: sign in again.
    case signedOut
    /// Things changed meanwhile (someone else is captain, the scene was picked, the member left,
    /// the coach was retired): the page reads the squad again.
    case outdated
    /// The member isn't in a squad any more.
    case noSquad
}
