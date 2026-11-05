import Testing

@testable import MeDomain

struct DeletionPhaseTests {
    @Test func takesATapOnlyWhileNothingIsRunning() {
        #expect(
            [DeletionPhase.reading, .deleting, .failed(.unavailable), .deleted].map(\.canConfirm) == [
                true, false, true, false,
            ])
    }
}
