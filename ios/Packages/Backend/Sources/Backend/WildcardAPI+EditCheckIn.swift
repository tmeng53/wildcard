import APIContract
import Contracts

// Editing and deleting the member's own check-ins.
extension WildcardAPI {
    /// Makes the member's own saved check-in `checkIn`: its fields and photos, uploaded first.
    /// The same edit again changes nothing, so a retry is safe.
    public func edit(_ checkIn: CheckIn) async throws(APIError) -> CheckIn {
        let saved = try await call {
            try await client.editCheckIn(path: .init(id: checkIn.id.description), body: .json(checkIn.edit)).ok
                .body.json
        }
        return try read { () throws(ContractsError) in try CheckIn(saved) }
    }

    /// Deletes the member's own check-in with its photos and what teammates left on it; fine when
    /// it is gone already.
    public func delete(_ checkIn: CheckInID) async throws(APIError) {
        try await call { _ = try await client.deleteCheckIn(path: .init(id: checkIn.description)).noContent }
    }
}
