/// A name or a line in each of the app's languages, as the server sends it (a sport, a 请假条
/// dice line, a broadcast), so the words change without an app release.
public struct CatalogNames: Hashable, Sendable {
    public let simplifiedChinese: String
    public let english: String
    public let traditionalChinese: String

    public init(simplifiedChinese: String, english: String, traditionalChinese: String) {
        (self.simplifiedChinese, self.english, self.traditionalChinese) = (
            simplifiedChinese, english, traditionalChinese
        )
    }

    /// Each language's words, for search.
    public var all: [String] { [simplifiedChinese, english, traditionalChinese] }

    /// The words in the first of `languages` (BCP 47, such as `zh-Hant-TW`) there are words in,
    /// else Simplified Chinese.
    public func localized(in languages: [String]) -> String {
        for language in languages {
            if language.hasPrefix("zh-Hant") || language == "zh-TW" || language == "zh-HK" { return traditionalChinese }
            if language.hasPrefix("zh") { return simplifiedChinese }
            if language.hasPrefix("en") { return english }
        }
        return simplifiedChinese
    }
}
