import Contracts
import Foundation

// Making and joining squads, the squad step of sign-up.
extension WildcardAPI {
    /// Makes a squad under its own id with the member in it. Safe to retry with the same id: the
    /// squad already made answers.
    public func createSquad(_ id: SquadID, named name: SquadName) async throws(APIError) -> Squad {
        let wire = try await call {
            switch try await client.createSquad(
                path: .init(squadId: id.description), body: .json(.init(version: ._1, name: name.text)))
            {
            case .created(let created): try created.body.json
            case .ok(let retried): try retried.body.json
            default: throw APIError.unreadableResponse
            }
        }
        return try read { () throws(ContractsError) in try Squad(wire) }
    }

    /// The squad an invite code belongs to, as the member sees it before joining.
    public func invite(_ code: InviteCode) async throws(APIError) -> SquadInvite {
        let wire = try await call {
            try await client.getSquadInvite(path: .init(inviteCode: code.text)).ok.body.json
        }
        return SquadInvite(
            name: wire.name, memberCount: wire.memberCount, isFull: wire.full, joined: wire.joined,
            looks: wire.looks.map(CharacterLook.init))
    }

    /// Joins the squad an invite code belongs to. Safe to repeat: a member already in it gets
    /// the squad.
    public func join(_ code: InviteCode) async throws(APIError) -> Squad {
        let wire = try await call {
            switch try await client.joinSquad(path: .init(inviteCode: code.text)) {
            case .created(let joined): try joined.body.json
            case .ok(let already): try already.body.json
            default: throw APIError.unreadableResponse
            }
        }
        return try read { () throws(ContractsError) in try Squad(wire) }
    }
}

/// A squad as its invite code shows it, before joining.
public struct SquadInvite: Hashable, Sendable {
    public let name: String
    public let memberCount: Int
    /// It has its 8 members and can't take more.
    public let isFull: Bool
    /// The member is in it already.
    public let joined: Bool
    /// The members' characters, the earliest to join first; members without one are left out.
    public let looks: [CharacterLook]
}
