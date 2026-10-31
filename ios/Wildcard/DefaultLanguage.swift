import Foundation

/// The app opens in Simplified Chinese even on a phone set to English, until the member picks a
/// language (`AppLanguage.pick`, or iOS Settings; both write the app's own `AppleLanguages`). To
/// undo it, delete this file and its call in `Launch`.
enum DefaultLanguage {
    static let identifier = "zh-Hans"
    private static let key = "AppleLanguages"

    /// Records Chinese as the app's language when none was chosen, by Settings or a launch
    /// argument. It runs before the app starts, since the system reads the app's languages once,
    /// the first time anything asks for one: set later, SwiftUI's text would follow but strings
    /// the code looks up, formatted dates and system controls (Sign in with Apple) would stay in
    /// the phone's language until the next launch, which is sign-up's.
    static func apply() {
        let arguments = ProcessInfo.processInfo.arguments
        guard !arguments.contains("-\(key)"), let bundle = Bundle.main.bundleIdentifier else { return }
        #if DEBUG
        // `-uitest-first-launch`: forget the recorded language, as on a new install.
        if arguments.contains("-uitest-first-launch") { UserDefaults.standard.removeObject(forKey: key) }
        #endif
        guard UserDefaults.standard.persistentDomain(forName: bundle)?[key] == nil else { return }
        UserDefaults.standard.set([identifier], forKey: key)
    }
}
