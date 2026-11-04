import Contracts
import Foundation
import Synchronization

/// The catalog's global switches (`AppCatalog.switches`), which a store on a switch follows:
/// POWDER DAY's pieces unlock only while `winter` is on, and while it is off its rack shows only
/// what the member holds. It starts empty, where every switch is on, and the app sets it at
/// launch and whenever it reads the API's catalog.
public final class StoreSwitches: Sendable {
    /// The app's switches.
    public static let shared = StoreSwitches()

    private let current = Mutex<[String: CatalogSwitch]>([:])

    public init() {}

    public func show(_ switches: [String: CatalogSwitch]) { current.withLock { $0 = switches } }

    /// Whether the switch `id` is on on `day`; one the catalog doesn't list is on.
    public func isOn(_ id: String, on day: LocalDay) -> Bool {
        current.withLock { $0[id] }.map { $0.isOn(day) } ?? true
    }

    /// Whether the switch `id` is on today in New York, where the switches' dates are.
    public func isOn(_ id: String) -> Bool {
        isOn(id, on: LocalDay(at: Date(), in: Self.newYork))
    }

    private static let newYork = TimeZone(identifier: "America/New_York") ?? .current
}
