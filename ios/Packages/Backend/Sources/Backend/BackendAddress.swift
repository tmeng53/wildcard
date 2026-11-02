import Foundation

/// Where a build finds its backend: our API and the auth provider, read from its Info.plist
/// (`WildcardAPIURL`, `WildcardAuthURL`, `WildcardAuthPublishableKey`), which Release build
/// settings fill in. The app and its 6pm push view read the same keys.
public struct BackendAddress: Sendable {
    public let apiURL: URL
    public let authURL: URL
    public let authPublishableKey: String

    public init(apiURL: URL, authURL: URL, authPublishableKey: String) {
        self.apiURL = apiURL
        self.authURL = authURL
        self.authPublishableKey = authPublishableKey
    }

    /// Nil when the build names no backend, as Debug builds don't.
    public init?(info: [String: Any]) {
        func value(_ key: String) -> String? {
            (info[key] as? String).flatMap { $0.isEmpty ? nil : $0 }
        }
        guard let api = value("WildcardAPIURL").flatMap(URL.init(string:)),
            let auth = value("WildcardAuthURL").flatMap(URL.init(string:)),
            let key = value("WildcardAuthPublishableKey")
        else { return nil }
        self.init(apiURL: api, authURL: auth, authPublishableKey: key)
    }
}
