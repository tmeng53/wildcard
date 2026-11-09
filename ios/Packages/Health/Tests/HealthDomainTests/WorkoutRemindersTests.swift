import Contracts
import Foundation
import HealthDomain
import Testing

private func workout(_ id: String, endingAt moment: String) throws -> ImportedWorkout {
    let end = try Timestamp(moment)
    return ImportedWorkout(
        workout: Workout(
            source: WorkoutSource(provider: WorkoutSource.appleHealth, id: id),
            startedAt: Timestamp(millisecondsSince1970: end.millisecondsSince1970 - 1_920_000), endedAt: end,
            summary: WorkoutSummary(durationSec: 1920, distanceM: 5200, avgHr: 148),
            route: [RoutePoint(lat: 40.7, lon: -74), RoutePoint(lat: 40.71, lon: -74)]),
        activity: .sport("run"))
}

private func context(posted: Set<WorkoutSource> = []) -> PostingContext {
    PostingContext(
        member: MemberID(UUID(uuid: (1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))),
        squad: SquadID(UUID(uuid: (2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2))), squadName: "周三不练腿俱乐部",
        timeZone: "America/New_York", posted: posted)
}

@Test func remindsOnlyOfTodaysFreshWorkoutsNotPostedOrRemindedYet() throws {
    // 6:42pm in New York on the 8th.
    let now = try Timestamp("2026-11-08T23:42:00Z").date
    let fresh = try workout("fresh", endingAt: "2026-11-08T23:37:00Z")
    let posted = try workout("posted", endingAt: "2026-11-08T23:00:00Z")
    let reminded = try workout("reminded", endingAt: "2026-11-08T22:30:00Z")
    // Ended this morning, synced only now: not news any more.
    let stale = try workout("stale", endingAt: "2026-11-08T14:00:00Z")
    let yesterday = try workout("yesterday", endingAt: "2026-11-08T04:30:00Z")
    let due = WorkoutReminders.due(
        [stale, fresh, posted, reminded, yesterday], context: context(posted: [posted.id]),
        reminded: [reminded.id], now: now)
    #expect(due.map(\.id.id) == ["fresh"])
}

@Test func aQuickPostStartsWithWhatSettingsSharesAndPostsTheMapAsCover() throws {
    var sharing = HealthSharing()
    sharing.heartRate = false
    let run = try workout("run", endingAt: "2026-11-08T23:37:00Z")
    let post = QuickPost(context: context(), day: try LocalDay("2026-11-08"), imported: run, sharing: sharing)
    #expect(post.activity == .sport("run"))
    #expect(post.imported.minutes?.value == 32)
    #expect(post.startsStruck == [.averageHeartRate, .maxHeartRate])
    let posted = post.posting(struck: post.startsStruck.union([.distance]))
    #expect(posted.summary.distanceM == nil)
    #expect(posted.summary.avgHr == nil)
    #expect(posted.summary.durationSec == 1920)
    #expect(posted.tilePosition == 1)
    // Stored as the reminder carries it.
    let decoded = try JSONDecoder().decode(QuickPost.self, from: JSONEncoder().encode(post))
    #expect(decoded == post)
}

@Test func aWorkoutOfNoListedSportHasNoSportToPostWith() throws {
    let other = ImportedWorkout(workout: try workout("other", endingAt: "2026-11-08T23:37:00Z").workout, activity: nil)
    let post = QuickPost(context: context(), day: try LocalDay("2026-11-08"), imported: other, sharing: HealthSharing())
    #expect(post.sport == nil)
    #expect(post.activity == nil)
}
