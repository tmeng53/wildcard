import CheckInDomain
import Contracts
import Foundation

/// The member's unlocks over our API, with what this phone has told kept in `told-unlocks.json`.
/// It is the member's: keep it in their `MemberFolders` folder, which signing out deletes.
public struct APIUnlockLedger: UnlockLedger {
    private let api: WildcardAPI
    private let file: URL

    /// - Parameter directory: where what was told is kept, such as the member's folder.
    public init(api: WildcardAPI, directory: URL) {
        self.api = api
        file = directory.appending(path: "told-unlocks.json")
    }

    public func unlocks() async throws(CheckInError) -> [Unlock] {
        do { return try await api.unlocks() } catch { throw CheckInError(error) }
    }

    public func told() async -> Set<String>? {
        guard let data = try? Data(contentsOf: file), let kept = try? JSONDecoder().decode(Kept.self, from: data),
            kept.version == 1
        else { return nil }
        return Set(kept.told)
    }

    public func keep(told: Set<String>) async {
        guard let data = try? JSONEncoder().encode(Kept(version: 1, told: told.sorted())) else { return }
        // Not kept, the phone tells these again on the next launch: better than never.
        try? DeviceJSON.write(data, to: file)
    }

    /// Stored JSON, so it carries a `version`.
    private struct Kept: Codable {
        let version: Int
        let told: [String]
    }
}
