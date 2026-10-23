import DailyPushDomain
import Foundation

/// Where the push view sends the member, left for the app in settings both processes share
/// (`AppGroup.defaults`): the view leaves it, then opens the app the way a tap on the push does,
/// and the app takes it once.
public struct PushDestinations: @unchecked Sendable {
    // UserDefaults is thread-safe (Apple documents it so), but not marked Sendable.
    private let defaults: UserDefaults
    private static let key = "dailyPush.destination"

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func leave(_ destination: PushDestination) {
        defaults.set(destination.rawValue, forKey: Self.key)
    }

    /// The destination left, once; nil when the push was opened some other way.
    public func take() -> PushDestination? {
        defer { defaults.removeObject(forKey: Self.key) }
        return defaults.string(forKey: Self.key).flatMap(PushDestination.init(rawValue:))
    }
}
