/// A squad the member is in.
public struct Squad: Hashable, Sendable {
    public let id: SquadID
    /// As its creator typed it.
    public let name: String
    /// Members share it to invite friends.
    public let inviteCode: String
    /// Who is in it now, the earliest to join first.
    public let members: [MemberID]

    public init(id: SquadID, name: String, inviteCode: String, members: [MemberID]) {
        self.id = id
        self.name = name
        self.inviteCode = inviteCode
        self.members = members
    }
}
