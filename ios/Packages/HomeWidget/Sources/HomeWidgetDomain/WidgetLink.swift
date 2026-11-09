import Foundation

/// A place in the app a widget opens: the widget hands the app its `url`, and the app reads it
/// back with `init?(url:)`.
public enum WidgetLink: String, CaseIterable, Sendable {
    /// 今天.
    case today
    /// 今天, with 打卡 open.
    case checkIn = "check-in"
    /// The coach's page over 今天.
    case coach

    private static let scheme = "wildcard"
    private static let host = "widget"

    public var url: URL {
        var parts = URLComponents()
        parts.scheme = Self.scheme
        parts.host = Self.host
        parts.path = "/" + rawValue
        guard let url = parts.url else { fatalError("a widget link is always a valid URL") }
        return url
    }

    /// Nil for any URL a widget didn't make, such as an invite link.
    public init?(url: URL) {
        guard url.scheme == Self.scheme, url.host() == Self.host else { return nil }
        self.init(rawValue: String(url.path().dropFirst()))
    }
}
