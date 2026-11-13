import APIContract
import Contracts
import Foundation

// Making and joining squads, the squad step of sign-up, and pats between squadmates.
extension WildcardAPI {
    /// Makes a squad under its own id with the member in it, its goal, 人均 `daysPerMember` 次
    /// (the API's 3 when nil), and its time zone (小队时区), an IANA name. Safe to retry with the
    /// same id: the squad already made answers.
    public func createSquad(
        _ id: SquadID, named name: SquadName, daysPerMember: Int? = nil, timeZone: String
    ) async throws(APIError) -> Squad {
        let wire = try await call {
            switch try await client.createSquad(
                path: .init(squadId: id.description),
                body: .json(
                    .init(version: ._1, name: name.text, daysPerMember: daysPerMember, timeZone: timeZone)))
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
            needsApproval: wire.needsApproval, looks: wire.looks.map(CharacterLook.init))
    }

    /// Joins the squad an invite code belongs to, or, for one whose captain lets members in
    /// (入队需要审核), asks them, with `note` (备注), withdrawing any request the member had waiting.
    /// Safe to repeat: a member already in it gets the squad, one who asked their request.
    public func join(_ code: InviteCode, note: JoinNote? = nil) async throws(APIError) -> JoinResult {
        enum Wire {
            case squad(Components.Schemas.Squad)
            case request(Components.Schemas.JoinRequest)
        }
        let wire = try await call {
            switch try await client.joinSquad(
                path: .init(inviteCode: code.text), body: .json(.init(version: ._1, note: note?.text)))
            {
            case .created(let joined): Wire.squad(try joined.body.json)
            case .ok(let already): Wire.squad(try already.body.json)
            case .accepted(let asked): Wire.request(try asked.body.json)
            default: throw APIError.unreadableResponse
            }
        }
        return try read { () throws(ContractsError) in
            switch wire {
            case .squad(let squad): .joined(try Squad(squad))
            case .request(let request): .asked(try JoinRequest(request))
            }
        }
    }

    /// The member's newest request to join a squad, waiting or ended; nil if they never asked.
    public func joinRequest() async throws(APIError) -> JoinRequest? {
        let wire = try await call { try await client.getMyJoinRequest().ok.body.json }
        return try read { () throws(ContractsError) in
            try wire.request.map { payload throws(ContractsError) in try JoinRequest(payload.value1) }
        }
    }

    /// 撤回申请: withdraws the member's waiting request. Safe to repeat.
    public func withdrawJoinRequest() async throws(APIError) {
        try await call {
            switch try await client.withdrawMyJoinRequest() {
            case .noContent: return
            default: throw APIError.unreadableResponse
            }
        }
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
    /// Joining asks its captain first (入队需要审核).
    public let needsApproval: Bool
    /// The members' characters, the earliest to join first; members without one are left out.
    public let looks: [CharacterLook]
}

/// What opening an invite did: joined the squad, or asked its captain to let the member in.
public enum JoinResult: Hashable, Sendable {
    case joined(Squad)
    case asked(JoinRequest)
}
