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

    /// The Mondays of every week the squad has a 战报 for, the latest first.
    public func weekStoryWeeks(of squad: SquadID) async throws(APIError) -> [LocalDay] {
        let body = try await call {
            try await client.listSquadWeekStories(path: .init(squadId: squad.description)).ok.body.json
        }
        do {
            return try body.weeks.map { try LocalDay($0.weekStart) }
        } catch {
            throw .unreadableResponse
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
