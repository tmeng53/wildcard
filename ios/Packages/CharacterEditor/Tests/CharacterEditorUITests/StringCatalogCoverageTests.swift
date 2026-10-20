import Foundation
import Testing

/// SwiftPM doesn't extract string keys, so a `Text` whose key is missing from the String Catalog
/// silently shows Chinese in English. This reads the editor's sources and catalog as files, so it
/// runs on Linux too.
struct StringCatalogCoverageTests {
    private static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let sources = packageRoot.appendingPathComponent("Sources/CharacterEditorUI")

    /// Every `Text("…", bundle: .module)`, and every display name `EditorNames` looks up.
    @Test func everyLocalizedTextHasAnEnglishEntry() throws {
        let keys = try Self.keys(matching: #"Text\("((?:[^"\\]|\\.)*)", bundle: \.module\)"#)
            .union(Self.keys(matching: #""[a-z]+(?:/[a-z]+)?": "([^"]+)""#))
        #expect(keys.count > 80, "found only \(keys.count) keys; are the patterns still right?")
        let missing = try keys.filter { try Self.english(for: $0) == nil }
        #expect(missing.isEmpty, "not in the String Catalog with English: \(missing.sorted())")
    }

    private static func english(for key: String) throws -> String? {
        let catalogURL = sources.appendingPathComponent("Resources/Localizable.xcstrings")
        let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as? [String: Any]
        let entry = (catalog?["strings"] as? [String: Any])?[key] as? [String: Any]
        let english = (entry?["localizations"] as? [String: Any])?["en"] as? [String: Any]
        let value = (english?["stringUnit"] as? [String: Any])?["value"] as? String
        return value.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The first capture of `pattern` across the sources, an interpolated Int written `%lld`.
    private static func keys(matching pattern: String) throws -> Set<String> {
        let expression = try NSRegularExpression(pattern: pattern)
        let files = try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        var keys = Set<String>()
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(match.range(at: 1), in: text) else { continue }
                keys.insert(
                    String(text[range]).replacingOccurrences(
                        of: #"\\\([^)]*\)"#, with: "%lld", options: .regularExpression))
            }
        }
        return keys
    }
}
