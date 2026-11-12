import Foundation
import Testing

/// SwiftPM doesn't extract string keys, so a `Text` whose key is missing from the String Catalog
/// silently shows Chinese in English. This reads HomeWidgetUI's sources and catalog as files, so it
/// runs on Linux too.
struct StringCatalogCoverageTests {
    private static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let sources = packageRoot.appendingPathComponent("Sources/HomeWidgetUI")
    private static let catalogURL = sources.appendingPathComponent("Resources/Localizable.xcstrings")

    @Test func everyLocalizedTextHasEnglishAndTraditionalChinese() throws {
        let keys = try Self.localizedKeys()
        #expect(keys.count > 20, "found only \(keys.count) keys; is the pattern still right?")
        for language in ["en", "zh-Hant"] {
            let missing = try keys.filter { try Self.value(for: $0, in: language) == nil }
            #expect(missing.isEmpty, "not in the String Catalog in \(language): \(missing.sorted())")
        }
    }

    /// The entry whose key matches, reading any interpolation (`%lld`, `%@`) as the same.
    private static func value(for key: String, in language: String) throws -> String? {
        let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as? [String: Any]
        let strings = catalog?["strings"] as? [String: Any]
        let entry = strings?.first { placeholders($0.key) == placeholders(key) }?.value as? [String: Any]
        let localized = (entry?["localizations"] as? [String: Any])?[language] as? [String: Any]
        let value = (localized?["stringUnit"] as? [String: Any])?["value"] as? String
        return value?.isEmpty == false ? value : nil
    }

    private static func placeholders(_ key: String) -> String {
        key.replacingOccurrences(of: "%lld", with: "%@")
    }

    /// Every key in `Text(copy: "…", bundle: .module)` and `String(copy: "…", bundle: .module)`,
    /// with each `\(…)` read as `%lld`.
    private static func localizedKeys() throws -> Set<String> {
        let pattern = try NSRegularExpression(
            pattern: #"(?:Text|String)\(copy:\s*"((?:[^"\\]|\\.)*)",\s*bundle: \.module\)"#)
        let interpolation = try NSRegularExpression(pattern: #"\\\([^)]*\)"#)
        let files = try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        var keys = Set<String>()
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(match.range(at: 1), in: text) else { continue }
                let raw = String(text[range])
                keys.insert(
                    interpolation.stringByReplacingMatches(
                        in: raw, range: NSRange(raw.startIndex..., in: raw), withTemplate: "%lld"))
            }
        }
        return keys
    }
}
