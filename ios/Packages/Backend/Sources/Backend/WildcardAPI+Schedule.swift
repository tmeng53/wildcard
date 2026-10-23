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
}
