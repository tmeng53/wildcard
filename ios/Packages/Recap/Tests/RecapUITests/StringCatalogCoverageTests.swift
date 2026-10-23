import Foundation
import Testing

/// SwiftPM doesn't extract string keys, so a `Text` whose key is missing from the String Catalog
/// silently shows Chinese in English. This reads RecapUI's sources and catalog as files, so it
/// runs on Linux too, where RecapUI itself doesn't build.
struct StringCatalogCoverageTests {
    private static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let sources = packageRoot.appendingPathComponent("Sources/RecapUI")
    private static let catalogURL = sources.appendingPathComponent("Resources/Localizable.xcstrings")

    @Test func everyLocalizedTextHasAnEnglishEntry() throws {
        let keys = try Self.localizedKeys()
        #expect(keys.count > 25, "found only \(keys.count) keys; is the pattern still right?")
        // An `Int` interpolation's key holds `%lld`, a `String`'s or a `Text`'s holds `%@`.
        let missing = try keys.filter {
            try Self.english(for: $0) == nil
                && Self.english(for: $0.replacingOccurrences(of: "%lld", with: "%@")) == nil
        }
        #expect(missing.isEmpty, "not in the String Catalog with English: \(missing.sorted())")
    }

    @Test func everyWeekdayHasAnEnglishLetter() throws {
        let letters = try ["一", "二", "三", "四", "五", "六", "日"].map { try Self.english(for: $0) }
        #expect(letters == ["M", "T", "W", "T", "F", "S", "S"])
    }

    /// SwiftLint's banned-terms rule can't read the catalog, so this covers its copy.
    @Test func catalogAvoidsBannedTerms() throws {
        let text = try String(contentsOf: Self.catalogURL, encoding: .utf8).lowercased()
        // Escaped, so the lint rule does not flag the test itself.
        for term in ["\u{5965}\u{8FD0}", "\u{6F}lympic"] {
            #expect(!text.contains(term), "the String Catalog uses a banned term")
        }
    }

    private static func english(for key: String) throws -> String? {
        let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as? [String: Any]
        let entry = (catalog?["strings"] as? [String: Any])?[key] as? [String: Any]
        let localized = (entry?["localizations"] as? [String: Any])?["en"] as? [String: Any]
        let value = (localized?["stringUnit"] as? [String: Any])?["value"] as? String
        return value?.isEmpty == false ? value : nil
    }

    /// Every key in `Text("…", bundle: .module)`, with each `\(…)` read as `%lld`.
    private static func localizedKeys() throws -> Set<String> {
        let pattern = try NSRegularExpression(pattern: #"Text\("((?:[^"\\]|\\.)*)", bundle: \.module\)"#)
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
