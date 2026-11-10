import Foundation

/// Lines put over the app's String Catalog, by key (the catalog's `appCopy` section), so a line
/// the app shows changes without a release. A key not here, or a language its line leaves out,
/// keeps the build's own words. The API checks each line keeps its key's placeholders; the app
/// checks again, so a line that doesn't is passed over and can never fill the wrong way.
public struct AppCopy: Hashable, Sendable, Codable {
    /// A line's words in the languages it changes in.
    public struct Words: Hashable, Sendable, Codable {
        public let simplifiedChinese: String?
        public let english: String?
        public let traditionalChinese: String?

        public init(simplifiedChinese: String? = nil, english: String? = nil, traditionalChinese: String? = nil) {
            (self.simplifiedChinese, self.english, self.traditionalChinese) = (
                simplifiedChinese, english, traditionalChinese
            )
        }

        // swiftlint:disable:next nesting
        private enum CodingKeys: String, CodingKey {
            case simplifiedChinese = "zhHans"
            case english = "en"
            case traditionalChinese = "zhHant"
        }

        /// The words for `language` (BCP 47, such as `zh-Hant`), if this line changes in it.
        public func words(in language: String) -> String? {
            if language.hasPrefix("zh-Hant") || language == "zh-TW" || language == "zh-HK" { return traditionalChinese }
            if language.hasPrefix("zh") { return simplifiedChinese }
            if language.hasPrefix("en") { return english }
            return nil
        }
    }

    /// The only `version` this build stores and reads.
    public static let currentVersion = 1

    public let version: Int
    public let entries: [String: Words]

    public init(entries: [String: Words]) {
        (version, self.entries) = (Self.currentVersion, entries)
    }

    /// Nothing put: every line is the build's own.
    public static let none = AppCopy(entries: [:])

    /// The words put for `key` in `language`, when they fill like the key; nil keeps the build's.
    public func words(for key: String, in language: String) -> String? {
        guard let words = entries[key]?.words(in: language), Self.fillsLike(key: key, words: words) else {
            return nil
        }
        return words
    }

    /// Each argument a format string takes, by its 1-based position: `lld`, `@`, `lf` as Swift
    /// writes an interpolation into a catalog key, or with an explicit position (`%2$@`). `%%`
    /// takes none.
    public static func formatArguments(_ text: String) -> [Int: String] {
        var found: [Int: String] = [:]
        var next = 1
        let specifier = /%(?:(\d+)\$)?[-+ #0]*\d*(?:\.\d+)?((?:hh|h|ll|l|q|z|t|j|L)?[@dDiuUxXoOfFeEgGcCsSpaA]|%)/
        for match in text.matches(of: specifier) {
            let conversion = String(match.output.2)
            guard conversion != "%" else { continue }
            if let explicit = match.output.1.flatMap({ Int($0) }) {
                found[explicit] = conversion
            } else {
                found[next] = conversion
                next += 1
            }
        }
        return found
    }

    /// Whether `words` take exactly the arguments `key` takes.
    public static func fillsLike(key: String, words: String) -> Bool {
        formatArguments(key) == formatArguments(words)
    }
}
