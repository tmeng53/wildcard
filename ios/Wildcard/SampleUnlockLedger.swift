import CheckInDomain
import Contracts

/// The sample member's unlocks, none told yet on this phone, so whatever the sample has (with
/// `-uitest-unlocked`, DEUCE CLUB) is told on the first load.
actor SampleUnlockLedger: UnlockLedger {
    private let all: [Unlock]
    private var kept: Set<String> = []

    init(unlocks: [Unlock]) {
        all = unlocks
    }

    func unlocks() async throws(CheckInError) -> [Unlock] { all }
    func told() async -> Set<String>? { kept }
    func keep(told: Set<String>) async { kept = told }
}
