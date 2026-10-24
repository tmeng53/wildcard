import Foundation

/// For now the app opens in Simplified Chinese even on a phone set to English, until the member
/// picks a language in iOS Settings (which writes the app's own `AppleLanguages`). To undo it,
/// delete this file and the two lines in `WildcardApp` that use it.
enum DefaultLanguage {
    static let identifier = "zh-Hans"

    /// True for this launch when no language was chosen for the app, by Settings or a launch
    /// argument; the choice is then recorded so later launches start in Chinese too.
    @MainActor static let applies: Bool = {
        let key = "AppleLanguages"
        guard !ProcessInfo.processInfo.arguments.contains("-\(key)"),
            let bundle = Bundle.main.bundleIdentifier,
            UserDefaults.standard.persistentDomain(forName: bundle)?[key] == nil
        else { return false }
        UserDefaults.standard.set([identifier], forKey: key)
        return true
    }()

    /// The locale the views use: Chinese on the launch that sets the default (the system reads the
    /// stored choice from the next launch on), the phone's own otherwise.
    @MainActor static var locale: Locale {
        applies ? Locale(identifier: identifier) : .current
    }
}
