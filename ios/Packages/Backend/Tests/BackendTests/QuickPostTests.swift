import CheckInDomain
import Contracts
import Foundation
import HealthDomain
import Testing

@testable import Backend

// A new workout posted from its reminder's card: the check-in it makes, and the handoff the app
// sends it from when it couldn't go out.

private func quickPost(sport: String? = "run") throws -> QuickPost {
    let end = try Timestamp("2026-11-08T23:37:00Z")
    let workout = Workout(
        source: WorkoutSource(provider: WorkoutSource.appleHealth, id: "run-1"),
        startedAt: Timestamp(millisecondsSince1970: end.millisecondsSince1970 - 1_920_000), endedAt: end,
        summary: WorkoutSummary(durationSec: 1920, distanceM: 5200, avgHr: 148))
    let context = PostingContext(
        member: MemberID(try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))),
        squad: SquadID(try #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333"))),
        squadName: "周三不练腿俱乐部", timeZone: "America/New_York", posted: [])
    return QuickPost(
        context: context, day: try LocalDay("2026-11-08"),
        imported: ImportedWorkout(workout: workout, activity: sport.map { .sport(Sport(stringLiteral: $0)) }),
        sharing: HealthSharing())
}

@Test func aQuickPostIsATrainingSharedToTheSquadWithoutWhatWasStruck() throws {
    let post = try quickPost()
    let id = CheckInID(UUID())
    let pending = try #require(
        APIQuickPoster.pending(post, struck: [.averageHeartRate], id: id, at: Timestamp(millisecondsSince1970: 0)))
    #expect(pending.id == id)
    #expect(pending.member == post.member)
    #expect(pending.day == post.day)
    #expect(pending.audience.squads == [post.squad])
    guard case .trained(let activity, let minutes, let body) = pending.draft else {
        Issue.record("not a training")
        return
    }
    #expect(activity == .sport("run"))
    #expect(minutes?.value == 32)
    #expect(body.photos.isEmpty)
    #expect(body.workout?.summary.avgHr == nil)
    #expect(body.workout?.summary.distanceM == 5200)
}

@Test func aWorkoutOfNoListedSportIsNotQuickPosted() throws {
    #expect(
        APIQuickPoster.pending(
            try quickPost(sport: nil), struck: [], id: CheckInID(UUID()), at: Timestamp(millisecondsSince1970: 0))
            == nil)
}

@Test func theHandoffGivesItsPostsToTheAppOnce() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: "wildcard-tests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let handoff = QuickPostHandoff(directory: directory)
    let post = try #require(
        APIQuickPoster.pending(
            try quickPost(), struck: [], id: CheckInID(UUID()), at: Timestamp(millisecondsSince1970: 0)))
    await handoff.keep(post)
    await handoff.keep(post)
    #expect(await handoff.takeAll().map(\.id) == [post.id])
    #expect(await handoff.takeAll().isEmpty)
    await handoff.keep(post)
    await handoff.drop(post.id)
    #expect(await handoff.takeAll().isEmpty)
}

@Test func aLineTypedUnderTheReminderGoesWithItOnOneLine() throws {
    let pending = try #require(
        APIQuickPoster.pending(
            try quickPost(), struck: [], caption: "  腿还在\n抖 ", id: CheckInID(UUID()),
            at: Timestamp(millisecondsSince1970: 0)))
    guard case .trained(_, _, let body) = pending.draft else {
        Issue.record("not a training")
        return
    }
    #expect(body.caption == "腿还在抖")
}
