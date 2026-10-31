import Foundation

/// The language the app speaks. iOS keeps an app's language in its `AppleLanguages` and reads it
/// once, as the app starts, so a pick made in the app (the open screen's globe, 设置's 语言) would
/// otherwise wait for the next launch. The app speaks it at once instead: views read it from the
/// environment's locale, which the app's root sets from here, and code that looks a string up or
/// formats one asks this type. The pick is stored as `AppleLanguages` too, so the next launch
/// and iOS itself (notifications, the app's page in Settings) agree.
public enum AppLanguage: String, CaseIterable, Sendable {
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case english = "en"

    private static let key = "AppleLanguages"

    /// The language's own name, the same in every language, as language pickers show it.
    public var name: String {
        switch self {
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        case .english: "English"
        }
    }

    /// The language the app speaks now: the first of the app's languages (picked in the app or
    /// iOS Settings, else the phone's) that it has. Traditional Chinese (`zh-Hant…`, or Taiwan's,
    /// Hong Kong's and Macau's `zh-TW`, `zh-HK`, `zh-MO`) reads as Traditional, any other Chinese
    /// as Simplified; a list with neither Chinese nor English, as Simplified.
    public static var current: AppLanguage {
        let preferred = UserDefaults.standard.stringArray(forKey: key) ?? Locale.preferredLanguages
        for tag in preferred {
            if tag.hasPrefix("zh-Hant") || ["zh-TW", "zh-HK", "zh-MO"].contains(tag) { return .traditionalChinese }
            if tag == "zh" || tag.hasPrefix("zh-") { return .simplifiedChinese }
            if tag == "en" || tag.hasPrefix("en-") { return .english }
        }
        return .simplifiedChinese
    }

    /// Speaks this language from now on, and from the next launch.
    public func pick() {
        UserDefaults.standard.set([rawValue], forKey: Self.key)
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    /// Records this language for the app's extensions (the 6pm push's view), in the settings the
    /// app shares with them: an extension is a process of its own, with its own `AppleLanguages`,
    /// so it would otherwise speak the phone's language. Nil (no shared settings) records nothing.
    public func share(in shared: UserDefaults?) {
        shared?.set(rawValue, forKey: Self.sharedKey)
    }

    /// For an extension, before it draws or looks a string up: speaks the language the app last
    /// shared from now on. With nothing shared (no shared settings, or the app hasn't recorded
    /// one yet) it keeps its own.
    public static func adopt(from shared: UserDefaults?) {
        guard let tag = shared?.string(forKey: sharedKey), let language = AppLanguage(rawValue: tag) else { return }
        UserDefaults.standard.set([language.rawValue], forKey: key)
    }

    private static let sharedKey = "appLanguage"

    /// Posted after a pick, for the app's root to draw everything again.
    public static let didChange = Notification.Name("AppLanguage.didChange")

    /// The locale strings are formatted in: this language, in the phone's region.
    public var locale: Locale {
        var components = Locale.Components(identifier: rawValue)
        components.region = Locale.current.region
        return Locale(components: components)
    }
}

extension Bundle {
    /// This bundle's strings in the language the app speaks now, for code that looks one up
    /// (`String(localized:bundle:)`, `localizedString(forKey:)`) rather than a `Text`.
    public var inAppLanguage: Bundle {
        let language = AppLanguage.current.rawValue
        guard let path = path(forResource: language, ofType: "lproj") else { return self }
        return Bundle(path: path) ?? self
    }
}
