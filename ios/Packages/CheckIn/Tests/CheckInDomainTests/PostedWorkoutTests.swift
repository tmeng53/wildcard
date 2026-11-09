import CheckInDomain
import Contracts
import Foundation
import Testing

@MainActor @Test func aPostedWorkoutStaysPostedWhetherSavedOrWaiting() async throws {
    let workout = Workout(
        source: WorkoutSource(provider: WorkoutSource.appleHealth, id: "A1"),
        startedAt: Timestamp(millisecondsSince1970: 1_792_513_000_000),
        endedAt: Timestamp(millisecondsSince1970: 1_792_515_000_000), summary: WorkoutSummary(durationSec: 1920))
    let fromHealth = CheckInDraft.trained(.sport("run"), nil, PostBody(photos: [], caption: "", workout: workout))
    let backend = ScriptedBackend()
    let today = store(backend)
    await today.load()
    #expect(today.postedWorkouts.isEmpty)

    await backend.set(failure: .notSent)
    _ = try await today.post(fromHealth)
    #expect(today.postedWorkouts == [workout.source])

    await backend.set(failure: nil)
    await today.load()
    #expect(today.pending.isEmpty)
    #expect(today.postedWorkouts == [workout.source])
    #expect(
        await backend.saves.last.flatMap { checkIn in
            if case .trained(let training) = checkIn.entry { training.workout } else { nil }
        } == workout)
}

@MainActor @Test func aPostMadeOutsideTheAppGoesOutOnceAndCountsAsPosted() async throws {
    let workout = Workout(
        source: WorkoutSource(provider: WorkoutSource.appleHealth, id: "B1"),
        startedAt: Timestamp(millisecondsSince1970: 1_792_513_000_000),
        endedAt: Timestamp(millisecondsSince1970: 1_792_515_000_000), summary: WorkoutSummary(durationSec: 1920))
    let backend = ScriptedBackend()
    let today = store(backend)
    await today.load()
    let member = try #require(today.home?.member)
    let day = try #require(today.day)
    let made = PendingCheckIn(
        id: CheckInID(UUID()), member: member, day: day, createdAt: Timestamp(millisecondsSince1970: 1_792_515_100_000),
        audience: try Audience([try #require(today.home?.squad.id)]),
        draft: .trained(.sport("run"), nil, PostBody(photos: [], caption: "", workout: workout)))
    let someoneElse = PendingCheckIn(
        id: CheckInID(UUID()), member: MemberID(UUID()), day: day, createdAt: made.createdAt,
        audience: made.audience, draft: made.draft)

    // Someone else's, left by an account signed out since, never goes out as this member's.
    await today.adopt([made, someoneElse, made])
    #expect(today.pending.isEmpty)
    #expect(await backend.saves.map(\.id) == [made.id])
    #expect(today.postedWorkouts == [workout.source])
}
