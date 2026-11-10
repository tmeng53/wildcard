import CheckInDomain
import Contracts
import Foundation
import HealthDomain
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

@MainActor @Test func postedWorkoutsAreKnownOnlyOnceTheServersHomeIsIn() async throws {
    // The phone's copy is from before the post; the server's has it.
    let workout = Workout(
        source: WorkoutSource(provider: WorkoutSource.appleHealth, id: "A1"),
        startedAt: Timestamp(millisecondsSince1970: 1_792_513_000_000),
        endedAt: Timestamp(millisecondsSince1970: 1_792_515_000_000), summary: WorkoutSummary(durationSec: 1920))
    let posted = CheckIn(
        id: CheckInID(UUID()), member: myID, day: tuesday, postedDay: tuesday,
        createdAt: Timestamp(tuesdayMorning), audience: try Audience([squadID]),
        entry: .trained(Training(activity: .sport("strength"), minutes: try WorkoutMinutes(32), workout: workout)))
    let backend = ScriptedBackend(saved: sampleHome(), server: sampleHome(checkIns: [posted]))
    await backend.set(failure: .notSent)
    let today = store(backend)
    await today.load()
    #expect(today.postedWorkouts.isEmpty)
    #expect(today.postedWorkoutsKnown == nil)

    await backend.set(failure: nil)
    await today.load()
    #expect(today.postedWorkoutsKnown == [workout.source])
}

@MainActor @Test func aTrainingPostedByHandIsKeptWithItsSportAndTime() async throws {
    let byHand = CheckIn(
        id: CheckInID(UUID()), member: myID, day: tuesday, postedDay: tuesday,
        createdAt: Timestamp(tuesdayMorning), audience: try Audience([squadID]),
        entry: .trained(Training(activity: .sport("pickleball"), minutes: try WorkoutMinutes(30))))
    let backend = ScriptedBackend(server: sampleHome(checkIns: [byHand]))
    let today = store(backend)
    await today.load()
    #expect(
        today.trainedByHand(on: tuesday)
            == [HandPostedTraining(activity: .sport("pickleball"), madeAt: Timestamp(tuesdayMorning))])
    #expect(today.trainedByHand(on: tuesday.adding(days: -1)).isEmpty)

    // One still waiting to go out counts too.
    await backend.set(failure: .notSent)
    _ = try await today.post(.trained(.sport("run"), nil, PostBody(photos: [], caption: "")))
    #expect(today.trainedByHand(on: tuesday).map(\.activity) == [.sport("pickleball"), .sport("run")])
}
