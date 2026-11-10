#if canImport(HealthKit) && os(iOS)
import Foundation
import HealthDomain
import HealthKit

extension HealthKitLibrary {
    /// Two long-running anchored queries, one on workouts and one on their routes, since a Watch
    /// saves a workout's route just after the workout itself. Each looks back as far as a read
    /// does, so its first answer, what Health holds already, stays small and is skipped.
    public func workoutChanges() -> AsyncStream<Void> {
        let (changes, teller) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        let since = Date().addingTimeInterval(-healthLookBackHours * 3600)
        let watching = Task { [store] in
            await withTaskGroup { group in
                group.addTask {
                    let recent = HKQuery.predicateForSamples(withStart: since, end: nil)
                    await Self.tell(
                        HKAnchoredObjectQueryDescriptor(predicates: [.workout(recent)], anchor: nil), in: store,
                        to: teller)
                }
                group.addTask {
                    let recent = HKQuery.predicateForSamples(withStart: since, end: nil)
                    await Self.tell(
                        HKAnchoredObjectQueryDescriptor(predicates: [.workoutRoute(recent)], anchor: nil), in: store,
                        to: teller)
                }
            }
            teller.finish()
        }
        teller.onTermination = { _ in watching.cancel() }
        return changes
    }

    /// Yields to `teller` for each change `query` sees after its first answer, until it fails or
    /// is cancelled.
    private static func tell<Sample: HKSample>(
        _ query: HKAnchoredObjectQueryDescriptor<Sample>, in store: HKHealthStore,
        to teller: AsyncStream<Void>.Continuation
    ) async {
        var answeredOnce = false
        do {
            for try await _ in query.results(for: store) {
                if answeredOnce { teller.yield() }
                answeredOnce = true
            }
        } catch {
            return
        }
    }
}
#endif
