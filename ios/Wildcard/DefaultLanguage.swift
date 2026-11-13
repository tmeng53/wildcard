import Foundation

/// The app opens in the phone's language when it is one the app speaks: English on a phone set to
/// English, Traditional Chinese on a phone set to it, and Simplified Chinese on any other, until
/// the member picks a language (`AppLanguage.pick`, or iOS Settings;
/// both write the app's own `AppleLanguages`). To undo it, delete this file and its call in
/// `Launch`.
enum DefaultLanguage {
    private static let key = "AppleLanguages"

    /// The language a new install opens in: English when the phone's own language is (`en…`),
    /// Traditional Chinese when it is (`zh-Hant…`, or Taiwan's, Hong Kong's and Macau's `zh-TW`,
    /// `zh-HK`, `zh-MO`), Simplified Chinese for any other.
    static func identifier(phone: [String]) -> String {
        guard let first = phone.first else { return "zh-Hans" }
        if first == "en" || first.hasPrefix("en-") { return "en" }
        let traditional = first.hasPrefix("zh-Hant") || ["zh-TW", "zh-HK", "zh-MO"].contains { first.hasPrefix($0) }
        return traditional ? "zh-Hant" : "zh-Hans"
    }

    /// Records the opening language as the app's when none was chosen, by Settings or a launch
    /// argument. It runs before the app starts, since the system reads the app's languages once,
    /// the first time anything asks for one: set later, SwiftUI's text would follow but strings
    /// the code looks up, formatted dates and system controls (Sign in with Apple) would stay in
    /// the phone's language until the next launch, which is sign-up's.
    static func apply() {
        let arguments = ProcessInfo.processInfo.arguments
        guard !arguments.contains("-\(key)"), let bundle = Bundle.main.bundleIdentifier else { return }
        #if DEBUG
        // `-uitest-first-launch`: forget the recorded language, as on a new install. Before the
        // phone's languages are read, since those start with the app's own: read first, the last
        // test's language would count as the phone's.
        if arguments.contains("-uitest-first-launch") { UserDefaults.standard.removeObject(forKey: key) }
        #endif
        var phone = Locale.preferredLanguages
        #if DEBUG
        // `-uitest-phone-language zh-Hant-TW`: a phone set to that language, as CI's simulator isn't.
        if let flag = arguments.firstIndex(of: "-uitest-phone-language"), arguments.indices.contains(flag + 1) {
            phone = [arguments[flag + 1]]
        }
        #endif
        guard UserDefaults.standard.persistentDomain(forName: bundle)?[key] == nil else { return }
        UserDefaults.standard.set([identifier(phone: phone)], forKey: key)
    }
}
