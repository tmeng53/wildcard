import Foundation

/// Where the app finds its backend: our API and the auth provider. Release build settings name
/// the hosted one through Info.plist; Debug names none, so it runs on the sample squad, unless
/// launched with `-local-backend`, which uses local Supabase and the API on this Mac
/// (`scripts/local-backend.sh`), reached from the simulator as 127.0.0.1.
struct AppConfig {
    let apiURL: URL
    let authURL: URL
    let authPublishableKey: String

    /// Nil when the build names no backend; the app then runs on the sample squad.
    static var current: AppConfig? {
        #if DEBUG
        if LaunchOptions.usesLocalBackend { return local }
        #endif
        let info = Bundle.main.infoDictionary ?? [:]
        func value(_ key: String) -> String? {
            (info[key] as? String).flatMap { $0.isEmpty ? nil : $0 }
        }
        guard let api = value("WildcardAPIURL").flatMap(URL.init(string:)),
            let auth = value("WildcardAuthURL").flatMap(URL.init(string:)),
            let key = value("WildcardAuthPublishableKey")
        else { return nil }
        return AppConfig(apiURL: api, authURL: auth, authPublishableKey: key)
    }

    #if DEBUG
    /// Local Supabase's default ports and its fixed, public development key, which the Supabase
    /// CLI gives every local stack.
    private static var local: AppConfig? {
        guard let api = URL(string: "http://127.0.0.1:8080"), let auth = URL(string: "http://127.0.0.1:54321")
        else { return nil }
        return AppConfig(
            apiURL: api, authURL: auth, authPublishableKey: "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH")
    }
    #endif
}
