import APIContract
import Contracts
import Foundation

// The squad's coach (小队设置's 教练): 教练招聘会, and the captain hiring, changing and firing it.
extension WildcardAPI {
    /// The coaches a squad can hire now (教练招聘会), with their 简历.
    public func coaches() async throws(APIError) -> [Coach] {
        let wire = try await call { try await client.listCoaches().ok.body.json }
        return try read { () throws(ContractsError) in
            try wire.coaches.map { card throws(ContractsError) in try Coach(card) }
        }
    }

    /// The squad's coach, if any, and whether the caller may hire.
    public func coach(of squad: SquadID) async throws(APIError) -> SquadCoach {
        let wire = try await call {
            try await client.getSquadCoach(path: .init(squadId: squad.description)).ok.body.json
        }
        return try read { () throws(ContractsError) in try SquadCoach(wire) }
    }

    /// Hires `coach`, firing the squad's other coach first (换教练); only the captain may. A
    /// retry for the coach it has answers as before.
    public func hire(_ coach: CoachID, for squad: SquadID) async throws(APIError) -> SquadCoach {
        let wire = try await call {
            switch try await client.hireSquadCoach(path: .init(squadId: squad.description), body: .json(coach.hire)) {
            case .created(let hired): try hired.body.json
            case .ok(let retried): try retried.body.json
            default: throw APIError.unreadableResponse
            }
        }
        return try read { () throws(ContractsError) in try SquadCoach(wire) }
    }

    /// Fires the squad's coach; only the captain may. Safe to repeat.
    public func fireCoach(of squad: SquadID) async throws(APIError) -> SquadCoach {
        let wire = try await call {
            try await client.fireSquadCoach(path: .init(squadId: squad.description)).ok.body.json
        }
        return try read { () throws(ContractsError) in try SquadCoach(wire) }
    }
}

// What the squad's coach said: its 战术板 line and its replies to check-ins.
extension WildcardAPI {
    /// The most check-ins one call asks about.
    public static let coachActivityLimit = 100

    /// The squad's newest 战术板 line, or nil before its coach wrote one, and its replies to
    /// `checkIns` (up to `coachActivityLimit`; the rest are left out). Members only.
    public func coachActivity(of squad: SquadID, about checkIns: [CheckInID] = []) async throws(APIError)
        -> CoachActivity
    {
        let asked = checkIns.prefix(Self.coachActivityLimit).map(\.description)
        let query = Operations.GetSquadCoachActivity.Input.Query(
            checkIns: asked.isEmpty ? nil : asked.joined(separator: ","))
        let wire = try await call {
            try await client.getSquadCoachActivity(path: .init(squadId: squad.description), query: query).ok.body
                .json
        }
        return try read { () throws(ContractsError) in try CoachActivity(wire) }
    }
}
