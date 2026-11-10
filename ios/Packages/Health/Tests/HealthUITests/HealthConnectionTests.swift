import Contracts
import Foundation
import HealthDomain
import HealthUI
import Testing

/// Health whose workouts and changes the test sets.
private actor FakeLibrary: HealthLibrary {
    nonisolated let changes: AsyncStream<Void>
    nonisolated let teller: AsyncStream<Void>.Continuation
    private let connected: Bool
    private var held: [ImportedWorkout] = []
    private(set) var stoppedListening = false
    private(set) var listens = 0

    init(connected: Bool) {
        self.connected = connected
        (changes, teller) = AsyncStream.makeStream(of: Void.self)
    }

    nonisolated var isAvailable: Bool { true }
    func isConnected() -> Bool { connected }
    func connect() -> Bool { connected }
    func workouts(endingFrom start: Date, to end: Date) -> [ImportedWorkout] { held }
    func hold(_ workouts: [ImportedWorkout]) { held = workouts }
    func stop() { stoppedListening = true }
    func listened() { listens += 1 }

    nonisolated func workoutChanges() -> AsyncStream<Void> {
        Task { await listened() }
        teller.onTermination = { [weak self] _ in Task { await self?.stop() } }
        return changes
    }
}

private func run(_ id: String) throws -> ImportedWorkout {
    let end = try Timestamp("2026-11-09T23:00:00Z")
    return ImportedWorkout(
        workout: Workout(
            source: WorkoutSource(provider: WorkoutSource.appleHealth, id: id),
            startedAt: Timestamp(millisecondsSince1970: end.millisecondsSince1970 - 1_800_000), endedAt: end,
            summary: WorkoutSummary(durationSec: 1800)),
        activity: .sport("run"))
}

/// Gives the follower's task turns until `done` holds, or fails after plenty.
@MainActor private func settle(until done: () async -> Bool) async {
    for _ in 0..<10_000 {
        if await done() { return }
        await Task.yield()
    }
    Issue.record("never settled")
}

@MainActor private func connection(_ library: FakeLibrary) -> HealthConnection {
    let defaults = UserDefaults(suiteName: "HealthConnectionTests-\(UUID().uuidString)") ?? .standard
    return HealthConnection(library: library, defaults: defaults, now: { Date(timeIntervalSince1970: 1_794_265_200) })
}

@MainActor @Test func followingReadsAgainOnEachChangeUntilCancelled() async throws {
    let library = FakeLibrary(connected: true)
    let health = connection(library)
    await health.refresh()
    #expect(health.recent.isEmpty)

    let following = Task { await health.followChanges() }
    await library.hold([try run("A")])
    library.teller.yield()
    await settle { health.recent.map(\.id.id) == ["A"] }

    await library.hold([try run("B"), try run("A")])
    library.teller.yield()
    await settle { health.recent.map(\.id.id) == ["B", "A"] }

    following.cancel()
    await following.value
    await settle { await library.stoppedListening }
    #expect(await library.listens == 1)
}

@MainActor @Test func followingReturnsAtOnceWhileHealthIsNotConnected() async throws {
    let library = FakeLibrary(connected: false)
    let health = connection(library)
    await health.followChanges()
    library.teller.yield()
    #expect(health.recent.isEmpty)
    // Give a stray listen the turns it would need to be counted.
    for _ in 0..<100 { await Task.yield() }
    #expect(await library.listens == 0)
}
