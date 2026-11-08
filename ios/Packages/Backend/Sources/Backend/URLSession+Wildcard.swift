import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension URLSession {
    /// The session the app's calls share: like `shared`, but a request that hears nothing from
    /// the server for `requestTimeout` (an idle timeout, reset by each piece that arrives) fails, so a screen shows its error (or 编几句 its dice
    /// lines) instead of waiting on (loader design A, 2026-10-24).
    public static let wildcard: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = requestTimeout
        return URLSession(configuration: configuration)
    }()

    /// Seconds without an answer before a request fails: `Loading.giveUpAfter` in the design system.
    public static let requestTimeout: TimeInterval = 15

    /// The session for the stream of live events (`GET /me/events`): it hears a heartbeat every
    /// 25 seconds while nothing happens, so it gives up only after a minute of silence.
    static let live: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        return URLSession(configuration: configuration)
    }()

    /// The session for a call the AI answers in its own time, the coach's letter (交接信), which
    /// 今天 waits on however long it takes (Tracy, 2026-11-08): it outwaits the server's own limit
    /// on the coach's run (two minutes).
    static let writing: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 150
        return URLSession(configuration: configuration)
    }()
}
