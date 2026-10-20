import Foundation
import Testing

/// SwiftPM doesn't extract string keys, so a `Text` whose key is missing from the String Catalog
/// silently shows Chinese in English. This reads the style guide's sources and the catalog as
/// files, so it runs on Linux too.
struct StringCatalogCoverageTests {
    private static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let sources = packageRoot.appendingPathComponent("Sources/DesignSystemUI")

    @Test func everyLocalizedTextHasAnEnglishEntry() throws {
        let catalogURL = Self.sources.appendingPathComponent("Resources/Localizable.xcstrings")
        let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as? [String: Any]
        let strings = try #require(catalog?["strings"] as? [String: Any])

        let keys = try Self.localizedKeys()
        #expect(keys.count > 40, "found only \(keys.count) keys; is the pattern still right?")
        let missing = keys.filter { key in
            let entry = strings[key] as? [String: Any]
            let english = (entry?["localizations"] as? [String: Any])?["en"] as? [String: Any]
            let value = (english?["stringUnit"] as? [String: Any])?["value"] as? String
            return value?.isEmpty ?? true
        }
        #expect(missing.isEmpty, "not in the String Catalog with English: \(missing.sorted())")
    }

    /// SwiftLint's banned-terms rule can't read the catalog, so this covers its copy.
    @Test func catalogAvoidsBannedTerms() throws {
        let catalogURL = Self.sources.appendingPathComponent("Resources/Localizable.xcstrings")
        let text = try String(contentsOf: catalogURL, encoding: .utf8).lowercased()
        // Escaped, so the lint rule does not flag the test itself.
        for term in ["\u{5965}\u{8FD0}", "\u{6F}lympic"] {
            #expect(!text.contains(term), "the String Catalog uses a banned term")
        }
    }

    /// Every key in `Text("…", bundle: .module)` across the style guide's sources.
    private static func localizedKeys() throws -> Set<String> {
        let pattern = try NSRegularExpression(pattern: #"Text\("((?:[^"\\]|\\.)*)", bundle: \.module\)"#)
        let files = try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        var keys = Set<String>()
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(text.startIndex..., in: text)
            for match in pattern.matches(in: text, range: range) {
                if let keyRange = Range(match.range(at: 1), in: text) {
                    // An interpolated Int becomes `%lld` in the catalog's key.
                    keys.insert(
                        String(text[keyRange]).replacingOccurrences(
                            of: #"\\\([^)]*\)"#, with: "%lld", options: .regularExpression))
                }
            }
        }
        return keys
    }
}
