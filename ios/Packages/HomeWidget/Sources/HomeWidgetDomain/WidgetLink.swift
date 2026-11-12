import Contracts
import Foundation

/// A place in the app a widget opens: the widget hands the app its `url`, and the app reads it
/// back with `init?(url:)`.
public enum WidgetLink: Hashable, Sendable {
    /// 今天.
    case today
    /// 今天, with 打卡 open.
    case checkIn
    /// The 训练 page, started from the workout Health synced, as 今天's Health card starts it:
    /// the capsule's 打卡. Nothing is posted until the member sends it there.
    case postWorkout(WorkoutSource)

    private static let scheme = "wildcard"
    private static let host = "widget"
    private static let provider = "provider"
    private static let workout = "workout"

    public var url: URL {
        var parts = URLComponents()
        parts.scheme = Self.scheme
        parts.host = Self.host
        switch self {
        case .today:
            parts.path = "/today"
        case .checkIn:
            parts.path = "/check-in"
        case .postWorkout(let source):
            parts.path = "/check-in"
            parts.queryItems = [
                URLQueryItem(name: Self.provider, value: source.provider),
                URLQueryItem(name: Self.workout, value: source.id),
            ]
        }
        guard let url = parts.url else { fatalError("a widget link is always a valid URL") }
        return url
    }

    /// Nil for any URL a widget didn't make, such as an invite link.
    public init?(url: URL) {
        guard url.scheme == Self.scheme, url.host() == Self.host,
            let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        let query = { (name: String) in parts.queryItems?.first { $0.name == name }?.value }
        switch parts.path {
        case "/today":
            self = .today
        case "/check-in":
            if let provider = query(Self.provider), let id = query(Self.workout) {
                self = .postWorkout(WorkoutSource(provider: provider, id: id))
            } else {
                self = .checkIn
            }
        default:
            return nil
        }
    }
}
