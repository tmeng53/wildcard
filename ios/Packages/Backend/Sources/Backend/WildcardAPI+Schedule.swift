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

    /// The squad's story of the week starting on `weekStart`: the titles once they are written.
    func weekStoryWire(of squad: SquadID, weekStart: LocalDay) async throws(APIError) -> Components.Schemas.WeekStory {
        try await call {
            try await client.getSquadWeekStory(
                path: .init(squadId: squad.description, weekStart: weekStart.description)
            ).ok.body.json
        }
    }
}
