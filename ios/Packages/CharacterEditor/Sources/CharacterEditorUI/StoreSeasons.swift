import Contracts
import Foundation
import Synchronization

/// The limited scenes' seasons from the catalog (`AppCatalog.seasons`), which a seasonal store
/// keeps: POWDER DAY is on the shopping street only while the winter scene is open. It starts
/// empty, where every store is on the street, and the app sets it at launch and whenever it reads
/// the API's catalog.
public final class StoreSeasons: Sendable {
    /// The app's seasons.
    public static let shared = StoreSeasons()

    private let current = Mutex<[String: SceneSeason]>([:])

    public init() {}

    public func show(_ seasons: [String: SceneSeason]) { current.withLock { $0 = seasons } }

    /// Whether `scene`'s season holds `day`; a scene with no season is open all year.
    public func isOpen(_ scene: String, on day: LocalDay) -> Bool {
        current.withLock { $0[scene] }.map { $0.contains(day) } ?? true
    }

    /// Whether `scene`'s season holds today in New York, where the seasons' dates are.
    public func isOpen(_ scene: String) -> Bool {
        isOpen(scene, on: LocalDay(at: Date(), in: Self.newYork))
    }

    private static let newYork = TimeZone(identifier: "America/New_York") ?? .current
}
