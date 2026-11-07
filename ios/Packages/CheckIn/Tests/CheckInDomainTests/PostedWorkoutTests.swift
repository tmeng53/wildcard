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
