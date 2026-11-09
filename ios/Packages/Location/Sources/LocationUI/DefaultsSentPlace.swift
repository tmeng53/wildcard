import Foundation
import LocationDomain

/// `SentPlace` in `UserDefaults`, as JSON with its version.
public struct DefaultsSentPlace: SentPlaceStore, @unchecked Sendable {  // UserDefaults is thread-safe.
    private let defaults: UserDefaults
    private static let key = "location.sent"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> SentPlace? {
        defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(SentPlace.self, from: $0) }
            .flatMap { $0.version == 1 ? $0 : nil }
    }

    public func save(_ place: SentPlace?) {
        guard let place, let data = try? JSONEncoder().encode(place) else {
            defaults.removeObject(forKey: Self.key)
            return
        }
        defaults.set(data, forKey: Self.key)
    }
}
