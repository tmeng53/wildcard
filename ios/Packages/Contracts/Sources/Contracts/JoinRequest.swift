/// A member's request to join a squad that needs its captain's OK (入队申请), as the member who
/// asked reads it: the squad as its invite showed it, and the captain who answers.
public struct JoinRequest: Hashable, Sendable {
    /// Where a request is: waiting for the captain, let in, turned away, or over another way
    /// (withdrawn, cancelled because they got into a squad, or anything a later API adds).
    public enum Status: Hashable, Sendable {
        case waiting
        case approved
        case declined
        case over
    }

    public let id: JoinRequestID
    public let squad: SquadID
    public let squadName: String
    /// What the member wrote the captain (备注).
    public let note: String?
    public let status: Status
    /// How many members the squad has now.
    public let memberCount: Int
    /// The members' characters, the earliest to join first; members without one are left out.
    public let looks: [CharacterLook]
    /// The captain, once they made a character.
    public let captain: MemberCharacter?

    public init(
        id: JoinRequestID, squad: SquadID, squadName: String, note: String?, status: Status, memberCount: Int,
        looks: [CharacterLook], captain: MemberCharacter?
    ) {
        (self.id, self.squad, self.squadName, self.note, self.status) = (id, squad, squadName, note, status)
        (self.memberCount, self.looks, self.captain) = (memberCount, looks, captain)
    }
}
