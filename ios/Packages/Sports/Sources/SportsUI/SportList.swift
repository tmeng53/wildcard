import Contracts
import Foundation
import Observation

/// The sports list this app shows now, the one every picker and label reads. It starts as the
/// copy the app keeps (the last one the API served, else the one it ships with) and changes when
/// a newer one arrives, so screens showing sports redraw.
@MainActor @Observable
public final class SportList {
    /// The app's list. The app sets it at launch and whenever it reads the API's.
    public static let shared = SportList()

    public private(set) var catalog: SportCatalog = .empty

    init() {}

    public func show(_ catalog: SportCatalog) {
        if catalog != self.catalog { self.catalog = catalog }
    }
}

extension SportCatalog.Names {
    /// The name in the language the app shows, as `Bundle.main` picks it.
    public var localized: String { localized(in: Bundle.main.preferredLocalizations) }

    /// The name in the first of `languages` the list has a name in, else Simplified Chinese.
    public func localized(in languages: [String]) -> String {
        for language in languages {
            if language.hasPrefix("zh-Hant") || language == "zh-TW" || language == "zh-HK" { return traditionalChinese }
            if language.hasPrefix("zh") { return simplifiedChinese }
            if language.hasPrefix("en") { return english }
        }
        return simplifiedChinese
    }
}
