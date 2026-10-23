import DailyPushDomain
import Foundation

/// Where the push view sends the member, left for the app in settings both processes share
/// (`AppGroup.defaults`): the view leaves it, then opens the app the way a tap on the push does,
/// and the app takes it once.
public struct PushDestinations: @unchecked Sendable {  // UserDefaults is thread-safe, though not marked Sendable.
    private let defaults: UserDefaults
    private static let key = "dailyPush.destination"
    private static let leftAt = "dailyPush.destinationLeftAt"
    /// How long a destination waits for the app: longer means the app didn't open from it, and
    /// a later tap on any notification shouldn't go there.
    static let fresh: TimeInterval = 60

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func leave(_ destination: PushDestination, at now: Date) {
        defaults.set(destination.rawValue, forKey: Self.key)
        defaults.set(now.timeIntervalSince1970, forKey: Self.leftAt)
    }

    /// The destination left in the last minute, once; nil when the push was opened some other way.
    public func take(at now: Date) -> PushDestination? {
        defer {
            defaults.removeObject(forKey: Self.key)
            defaults.removeObject(forKey: Self.leftAt)
        }
        let left = Date(timeIntervalSince1970: defaults.double(forKey: Self.leftAt))
        guard abs(now.timeIntervalSince(left)) <= Self.fresh else { return nil }
        return defaults.string(forKey: Self.key).flatMap(PushDestination.init(rawValue:))
    }
}
