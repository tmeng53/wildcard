import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension URLSession {
    /// The session the app's calls share: like `shared`, but a request the server leaves
    /// unanswered for `requestTimeout` fails, so a screen shows its error (or 编几句 its dice
    /// lines) instead of waiting on (loader design A, 2026-10-24).
    public static let wildcard: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = requestTimeout
        return URLSession(configuration: configuration)
    }()

    /// Seconds without an answer before a request fails: `Loading.giveUpAfter` in the design system.
    public static let requestTimeout: TimeInterval = 15
}
