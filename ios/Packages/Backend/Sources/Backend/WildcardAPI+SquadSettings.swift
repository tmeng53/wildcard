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
        let body = scene.pick()
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

    /// The squad's weekly goal (人均 N 次), this week's and next, and its recent average.
    public func weeklyGoal(of squad: SquadID) async throws(APIError) -> SquadWeeklyGoal {
        let wire = try await call {
            try await client.getSquadWeeklyGoal(path: .init(squadId: squad.description)).ok.body.json
        }
        return SquadWeeklyGoal(wire)
    }

    /// Sets the squad's weekly goal from next week; only its captain may. Safe to repeat.
    public func setWeeklyGoal(of squad: SquadID, to daysPerMember: Int) async throws(APIError) -> SquadWeeklyGoal {
        let wire = try await call {
            try await client.setSquadWeeklyGoal(
                path: .init(squadId: squad.description), body: .json(SquadWeeklyGoal.change(to: daysPerMember))
            ).ok.body.json
        }
        return SquadWeeklyGoal(wire)
    }

    /// The squad's time zone (小队时区) this week and next.
    public func timeZone(of squad: SquadID) async throws(APIError) -> SquadTimeZone {
        let wire = try await call {
            try await client.getSquadTimeZone(path: .init(squadId: squad.description)).ok.body.json
        }
        return SquadTimeZone(wire)
    }

    /// Sets the squad's time zone from the squad's next week; only its captain may. Safe to repeat.
    public func setTimeZone(of squad: SquadID, to timeZone: String) async throws(APIError) -> SquadTimeZone {
        let wire = try await call {
            try await client.setSquadTimeZone(
                path: .init(squadId: squad.description), body: .json(SquadTimeZone.change(to: timeZone))
            ).ok.body.json
        }
        return SquadTimeZone(wire)
    }

    /// The squad's language (小队语言): the captain's pick, else the captain's app language.
    public func language(of squad: SquadID) async throws(APIError) -> SquadLanguage {
        let wire = try await call {
            try await client.getSquadLanguage(path: .init(squadId: squad.description)).ok.body.json
        }
        return SquadLanguage(wire)
    }

    /// Sets the squad's language from now on; only its captain may. Safe to repeat.
    public func setLanguage(of squad: SquadID, to language: SquadLanguage.Language) async throws(APIError)
        -> SquadLanguage
    {
        let wire = try await call {
            try await client.setSquadLanguage(
                path: .init(squadId: squad.description), body: .json(SquadLanguage.change(to: language))
            ).ok.body.json
        }
        return SquadLanguage(wire)
    }
    // MARK: 入队申请

    /// The requests waiting for the captain, the earliest first; only the captain may read them.
    public func joinRequests(of squad: SquadID) async throws(APIError) -> [WaitingJoinRequest] {
        let wire = try await call {
            try await client.listSquadJoinRequests(path: .init(squadId: squad.description)).ok.body.json
        }
        return try read { () throws(ContractsError) in try wire.requests.map(WaitingJoinRequest.init) }
    }

    /// Lets a member in (`approve`) or turns them away; only the captain may. Answering again the
    /// same way is a success.
    public func answer(_ request: JoinRequestID, in squad: SquadID, approve: Bool) async throws(APIError) {
        try await call {
            _ = try await client.answerSquadJoinRequest(
                path: .init(squadId: squad.description, requestId: request.description),
                body: .json(.init(version: ._1, approve: approve))
            ).ok.body.json
        }
    }

    /// Whether joining the squad needs its captain's OK (入队需要审核).
    public func joinApproval(of squad: SquadID) async throws(APIError) -> Bool {
        try await call {
            try await client.getSquadJoinApproval(path: .init(squadId: squad.description)).ok.body.json.required
        }
    }

    /// Turns 入队需要审核 on or off; only the captain may. Safe to repeat.
    public func setJoinApproval(of squad: SquadID, required: Bool) async throws(APIError) -> Bool {
        try await call {
            try await client.setSquadJoinApproval(
                path: .init(squadId: squad.description), body: .json(.init(version: ._1, required: required))
            ).ok.body.json.required
        }
    }
}
