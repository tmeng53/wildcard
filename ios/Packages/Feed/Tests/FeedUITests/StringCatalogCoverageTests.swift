import Foundation
import Testing

@testable import FeedUI

/// SwiftPM doesn't extract string keys, so a `Text` whose key is missing from the String Catalog
/// silently shows Chinese in English. This reads FeedUI's sources and catalog as files, so it
/// runs on Linux too.
struct StringCatalogCoverageTests {
    private static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let sources = packageRoot.appendingPathComponent("Sources/FeedUI")
    private static let catalogURL = sources.appendingPathComponent("Resources/Localizable.xcstrings")

    @Test func everyLocalizedTextHasAnEnglishEntry() throws {
        let keys = try Self.localizedKeys()
        #expect(keys.count > 20, "found only \(keys.count) keys; is the pattern still right?")
        let missing = try keys.filter { key in
            try Self.spellings(of: key).allSatisfy { try Self.english(for: $0) == nil }
        }
        #expect(missing.isEmpty, "not in the String Catalog with English: \(missing.sorted())")
    }

    /// The sample squad's captions and 请假条 read in English too, within their limits.
    @Test func sampleLinesHaveEnglishThatFits() throws {
        let source = try String(
            contentsOf: Self.sources.appendingPathComponent("InMemoryFeedSource+Sample.swift"), encoding: .utf8)
        let pattern = try NSRegularExpression(pattern: #"(?:, |localized\()"([^"]*\p{Han}[^"]*)"\)"#)
        let keys = pattern.matches(in: source, range: NSRange(source.startIndex..., in: source)).compactMap {
            Range($0.range(at: 1), in: source).map { String(source[$0]) }
        }
        #expect(keys.count == 11)
        for key in keys {
            let english = try #require(try Self.english(for: key), "\(key) has no English")
            #expect(english.count <= 80, "\(english)")
        }
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
            pattern: #"(?:Text|String)\((?:localized: )?"((?:[^"\\]|\\.)*)", bundle: \.module\)"#)
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
