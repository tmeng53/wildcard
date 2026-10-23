import APIContract
import Contracts
import Foundation

// Squad settings (小队设置): the squad as its members see it, the captain's changes, leaving,
// and the week's scene.
extension WildcardAPI {
    public func squad(_ id: SquadID) async throws(APIError) -> Squad {
        let wire = try await call { try await client.getSquad(path: .init(squadId: id.description)).ok.body.json }
        return try read { () throws(ContractsError) in try Squad(wire) }
    }

    /// Renames the squad; only its captain may.
    public func rename(_ squad: SquadID, to name: SquadName) async throws(APIError) -> Squad {
        let wire = try await call {
            try await client.renameSquad(
                path: .init(squadId: squad.description), body: .json(.init(version: ._1, name: name.text))
            ).ok.body.json
        }
        return try read { () throws(ContractsError) in try Squad(wire) }
    }

    /// Hands the captaincy to another member; only the captain may.
    public func handCaptaincy(of squad: SquadID, to member: MemberID) async throws(APIError) -> Squad {
        let wire = try await call {
            try await client.handSquadCaptaincy(
                path: .init(squadId: squad.description),
                body: .json(.init(version: ._1, member: member.description))
            ).ok.body.json
        }
        return try read { () throws(ContractsError) in try Squad(wire) }
    }

    /// Takes a member out of the squad: the caller themselves (leaving), or anyone, for the
    /// captain. Safe to repeat.
    public func remove(_ member: MemberID, from squad: SquadID) async throws(APIError) {
        _ = try await call {
            try await client.removeSquadMember(
                path: .init(squadId: squad.description, memberId: member.description)
            ).noContent
        }
    }

    /// The squad's scene this week and who picks it.
    public func scene(of squad: SquadID) async throws(APIError) -> SquadScene {
        let wire = try await call {
            try await client.getSquadScene(path: .init(squadId: squad.description)).ok.body.json
        }
        return try read { () throws(ContractsError) in try SquadScene(wire) }
    }

    /// Picks the scene for the week open now, once. A retry of the same pick answers as before.
    public func pick(_ scene: SceneID, for squad: SquadID, week: LocalDay) async throws(APIError) -> SquadScene {
        let body = try read { () throws(ContractsError) in try scene.pick() }
        let wire = try await call {
            switch try await client.pickSquadScene(
                path: .init(squadId: squad.description, weekStart: week.description), body: .json(body))
            {
            case .created(let picked): try picked.body.json
            case .ok(let retried): try retried.body.json
            default: throw APIError.unreadableResponse
            }
        }
        return try read { () throws(ContractsError) in try SquadScene(wire) }
    }
}
