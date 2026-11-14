import Contracts

// Reading a request to join a squad (入队申请) from the API's wire types.

extension JoinRequest {
    public init(_ wire: Components.Schemas.JoinRequest) throws(ContractsError) {
        self.init(
            id: try JoinRequestID(wire: wire.id), squad: try SquadID(wire: wire.squadId), squadName: wire.squadName,
            note: wire.note, status: Status(wire: wire.status), memberCount: wire.memberCount,
            looks: wire.looks.map(CharacterLook.init),
            captain: try wire.captain.map { captain throws(ContractsError) in
                MemberCharacter(nickname: try Nickname(captain.nickname), look: CharacterLook(captain.look))
            })
    }
}

extension JoinRequest.Status {
    /// The API may add ways a request ends; this build reads any it doesn't know as over.
    init(wire: String) {
        switch wire {
        case "waiting": self = .waiting
        case "approved": self = .approved
        case "declined": self = .declined
        default: self = .over
        }
    }
}

extension WaitingJoinRequest {
    public init(_ wire: Components.Schemas.WaitingJoinRequest) throws(ContractsError) {
        let character: MemberCharacter? =
            if let nickname = wire.nickname, let look = wire.look {
                MemberCharacter(nickname: try Nickname(nickname), look: CharacterLook(look))
            } else {
                nil
            }
        self.init(
            id: try JoinRequestID(wire: wire.id), member: try MemberID(wire: wire.member), character: character,
            note: wire.note, askedAt: wire.askedAt)
    }
}
