import Contracts
import Foundation

// Making and joining squads, the squad step of sign-up, and pats between squadmates.
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

    // MARK: - 拍一拍

    /// Whom the member patted today in `squad`, and who patted them in the last day.
    public func pokes(in squad: SquadID) async throws(APIError) -> SquadPokes {
        let wire = try await call {
            try await client.listSquadNudges(path: .init(squadId: squad.description), query: .init(kind: .poke))
                .ok.body.json
        }
        return try read { () throws(ContractsError) in try SquadPokes(wire) }
    }

    /// Pats a squadmate. Once a day each: patting them again the same day changes nothing.
    public func pat(_ member: MemberID, in squad: SquadID) async throws(APIError) {
        try await call {
            switch try await client.nudgeSquadmate(
                path: .init(squadId: squad.description),
                body: .json(.init(version: ._1, to: member.description, kind: .poke)))
            {
            case .ok, .created: return
            default: throw APIError.unreadableResponse
            }
        }
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
