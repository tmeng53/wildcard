import Backend
import Foundation

/// Where the app finds its backend. Release build settings name the hosted one through
/// Info.plist; Debug names none, so it runs on the sample squad, unless launched with
/// `-local-backend`, which uses local Supabase and the API on this Mac
/// (`scripts/local-backend.sh`), reached from the simulator as 127.0.0.1.
enum AppConfig {
    /// Nil when the build names no backend; the app then runs on the sample squad.
    static var current: BackendAddress? {
        #if DEBUG
        if LaunchOptions.usesLocalBackend { return local }
        #endif
        return BackendAddress(info: Bundle.main.infoDictionary ?? [:])
    }

    #if DEBUG
    /// Local Supabase's default ports and its fixed, public development key, which the Supabase
    /// CLI gives every local stack.
    private static var local: BackendAddress? {
        guard let api = URL(string: "http://127.0.0.1:8080"), let auth = URL(string: "http://127.0.0.1:54321")
        else { return nil }
        return BackendAddress(
            apiURL: api, authURL: auth, authPublishableKey: "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH")
    }
    #endif
}
