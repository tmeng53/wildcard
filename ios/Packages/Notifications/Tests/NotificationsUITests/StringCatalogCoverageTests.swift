import Foundation
import Testing

@testable import NotificationsUI

/// SwiftPM doesn't extract string keys, so a `Text` whose key is missing from the String Catalog
/// silently shows Chinese in English. This reads NotificationsUI's sources and catalog as files, so it
/// runs on Linux too.
struct StringCatalogCoverageTests {
    private static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let sources = packageRoot.appendingPathComponent("Sources/NotificationsUI")
    private static let catalogURL = sources.appendingPathComponent("Resources/Localizable.xcstrings")

    @Test func everyLocalizedTextHasAnEnglishEntry() throws {
        let keys = try Self.localizedKeys()
        #expect(keys.count > 15, "found only \(keys.count) keys; is the pattern still right?")
        let missing = try keys.filter { key in
            try Self.spellings(of: key).allSatisfy { try Self.english(for: $0) == nil }
        }
        #expect(missing.isEmpty, "not in the String Catalog with English: \(missing.sorted())")
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

    /// A key with each `%lld` read either way: an `Int` interpolation's key holds `%lld`, a
    /// `String`'s or a `Text`'s holds `%@`.
    private static func spellings(of key: String) -> [String] {
        let parts = key.components(separatedBy: "%lld")
        var spellings = [parts[0]]
        for part in parts.dropFirst() {
            spellings = spellings.flatMap { [$0 + "%lld" + part, $0 + "%@" + part] }
        }
        return spellings
    }

    /// Every key in `Text("…", bundle: .module)` and `String(localized: "…", bundle: .module)`,
    /// with each `\(…)` read as `%lld`.
    private static func localizedKeys() throws -> Set<String> {
        let pattern = try NSRegularExpression(
            pattern: #"(?:Text|String)\(copy: "((?:[^"\\]|\\.)*)", bundle: \.module\)"#)
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
