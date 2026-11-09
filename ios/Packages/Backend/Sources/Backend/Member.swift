import APIContract
import Contracts
import Foundation

/// A member as the API knows them.
public struct Member: Hashable, Sendable {
    public let id: MemberID
    /// Nil until it is first saved, right after signing up.
    public let profile: Profile?
    /// When the profile was first saved, right after signing up. Nil until then.
    public let joinedAt: Timestamp?
    /// Whether the member is on the admin list: the app shows them tools only admins need.
    public let isAdmin: Bool
    /// The birthday they chose to give, saved and removed apart from the profile. Nil without one.
    public let birthday: Birthday?
}

/// What the member tells the API about themselves.
public struct Profile: Hashable, Sendable {
    /// Where the member lives, for their weekly reset.
    public let timeZone: TimeZone
    /// What their character shouts when the squad cheers a teammate's 练了. Nil until they pick
    /// one, and the app uses their persona's own line.
    public let catchphrase: Catchphrase?
    /// Their nickname and character's look. Nil until they make it, right after signing in.
    /// A save without it clears it, since the profile is saved whole.
    public let character: MemberCharacter?
    /// The number on their player card. Nil until they pick one, and the card shows their place
    /// in their squad.
    public let jerseyNumber: JerseyNumber?

    public init(
        timeZone: TimeZone, catchphrase: Catchphrase? = nil, character: MemberCharacter? = nil,
        jerseyNumber: JerseyNumber? = nil
    ) {
        self.timeZone = timeZone
        self.catchphrase = catchphrase
        self.character = character
        self.jerseyNumber = jerseyNumber
    }

    init(
        timeZone identifier: String, catchphrase: String?, character: Components.Schemas.Character?,
        jerseyNumber: Int?
    ) throws(APIError) {
        guard let timeZone = TimeZone(identifier: identifier) else { throw .unreadableResponse }
        do {
            self.init(
                timeZone: timeZone,
                catchphrase: try catchphrase.map { text throws(ContractsError) in try Catchphrase(text) },
                character: try character.map { wire throws(ContractsError) in try MemberCharacter(wire) },
                jerseyNumber: try jerseyNumber.map { number throws(ContractsError) in try JerseyNumber(number) })
        } catch {
            throw .unreadableResponse
        }
    }

    init(_ wire: Components.Schemas.Me.ProfilePayload) throws(APIError) {
        try self.init(
            timeZone: wire.timeZone, catchphrase: wire.catchphrase, character: wire.character,
            jerseyNumber: wire.jerseyNumber)
    }
}
