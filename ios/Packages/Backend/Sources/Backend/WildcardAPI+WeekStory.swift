import APIContract
import Contracts
import Foundation

// The Sunday 战报: a squad's story for a week, and nudging the organisers when the titles are late.
extension WildcardAPI {
    /// 催一下主办方: asks for the week's late titles to be tried again. Fine to repeat, and once
    /// the titles are written.
    public func nudgeWeekStory(of squad: SquadID, week monday: LocalDay) async throws(APIError) {
        try await call {
            _ = try await client.nudgeSquadWeekStory(
                path: .init(squadId: squad.description, weekStart: monday.description)
            ).noContent
        }
    }

    func weekStoryWire(of squad: SquadID, week monday: LocalDay) async throws(APIError) -> Components.Schemas.WeekStory
    {
        try await call {
            try await client.getSquadWeekStory(path: .init(squadId: squad.description, weekStart: monday.description))
                .ok.body.json
        }
    }
}
