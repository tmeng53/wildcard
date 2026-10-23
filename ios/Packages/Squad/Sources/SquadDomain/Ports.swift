import Contracts

/// Everything 小队设置 shows, read together.
public struct SquadSettings: Hashable, Sendable {
    public var squad: Squad
    /// The signed-in member.
    public let viewer: MemberID
    /// Each member's nickname and character; a member who hasn't made theirs yet is missing.
    public var characters: [MemberID: MemberCharacter]
    public var scene: SquadScene

    public init(squad: Squad, viewer: MemberID, characters: [MemberID: MemberCharacter], scene: SquadScene) {
        self.squad = squad
        self.viewer = viewer
        self.characters = characters
        self.scene = scene
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
}

/// What can go wrong on 小队设置, by what the member can do about it.
public enum SquadError: Error, Hashable, Sendable {
    /// No connection, or the server is down: try again.
    case unavailable
    /// The session ended: sign in again.
    case signedOut
    /// Things changed meanwhile (someone else is captain, the scene was picked, the member left):
    /// the page reads the squad again.
    case outdated
    /// The member isn't in a squad any more.
    case noSquad
}
