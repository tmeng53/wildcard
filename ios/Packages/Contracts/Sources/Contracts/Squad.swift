/// A squad the member is in.
public struct Squad: Hashable, Sendable {
    public let id: SquadID
    /// As its creator typed it.
    public let name: String
    /// Members share it to invite friends.
    public let inviteCode: String
    /// Who is in it now, the earliest to join first.
    public let members: [MemberID]
    /// The captain (队长), who renames the squad, removes members and hands the captaincy on.
    /// Nil only once everyone has left.
    public let captain: MemberID?

    public init(id: SquadID, name: String, inviteCode: String, members: [MemberID], captain: MemberID?) {
        self.id = id
        self.name = name
        self.inviteCode = inviteCode
        self.members = members
        self.captain = captain
    }
}

/// The squad a member in none was last in, and how they came out of it.
public struct SquadExit: Hashable, Sendable {
    /// How a member came out of a squad.
    public enum How: Hashable, Sendable {
        /// They left it themselves (the captain who disbanded it too).
        case left
        /// Its captain took them out.
        case removed
        /// Its captain disbanded it (解散小队), taking everyone out.
        case disbanded
    }

    public let id: SquadID
    public let name: String
    public let how: How

    public init(id: SquadID, name: String, how: How) {
        (self.id, self.name, self.how) = (id, name, how)
    }
}
