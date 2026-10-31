import APIContract
import Contracts
import Foundation

extension WildcardAPI {
    /// Replaces the member's 饮食小目标 for the week starting on `weekStart`, a Monday.
    func saveFuelGoalsWire(_ goals: Components.Schemas.FuelGoals, weekStart: LocalDay) async throws(APIError) {
        _ = try await call {
            try await client.saveMyFuelGoals(
                path: .init(weekStart: weekStart.description), body: .json(.init(version: ._1, goals: goals))
            ).ok.body.json
        }
    }

    /// The member's typical week (我的一周): seven days, Monday first, which the weeks to come
    /// follow until one is changed for itself; the default before they make one.
    public func planTemplate() async throws(APIError) -> [PlanDay] {
        let wire = try await call { try await client.getMyPlanTemplate().ok.body.json }
        return try read { () throws(ContractsError) in try [PlanDay](wire: wire.days) }
    }

    /// Saves the member's typical week. The first, made at sign-up, is this week's plan too; a
    /// change applies from next week.
    public func saveTemplate(_ days: [PlanDay]) async throws(APIError) {
        _ = try await call { try await client.saveMyPlanTemplate(body: .json(.init(days))).ok }
    }
}
