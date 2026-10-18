import Contracts
import Foundation
import Testing

/// SwiftPM doesn't extract string keys, so a `Text` whose key is missing from the String Catalog
/// silently shows Chinese in English. This reads CheckInUI's sources and catalog as files, so
/// it runs on Linux too.
struct StringCatalogCoverageTests {
    private static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let sources = packageRoot.appendingPathComponent("Sources/CheckInUI")

    @Test func everyLocalizedTextHasAnEnglishEntry() throws {
        let keys = try Self.localizedKeys()
        #expect(keys.count > 20, "found only \(keys.count) keys; is the pattern still right?")
        let missing = try keys.filter { try Self.english(for: $0) == nil }
        #expect(missing.isEmpty, "not in the String Catalog with English: \(missing.sorted())")
    }

    @Test func everySportAndCategoryHasAChineseAndEnglishName() throws {
        let keys =
            Sport.allCases.map { "sport.\($0.rawValue)" }
            + SportCategory.allCases.map { "sportCategory.\($0.rawValue)" }
        #expect(keys.count == 64)
        let missing = try keys.filter { try Self.english(for: $0) == nil || Self.value(for: $0, in: "zh-Hans") == nil }
        #expect(missing.isEmpty, "sports without both names: \(missing)")
        #expect(try Self.value(for: "sport.pickleball", in: "zh-Hans") == "匹克球")
        #expect(try Self.english(for: "sportCategory.everyday") == "Everyday counts")
    }

    @Test func diceLinesHaveEnglish() throws {
        let source = try String(
            contentsOf: Self.sources.appendingPathComponent("DiceDisclaimerWriter.swift"), encoding: .utf8)
        #expect(source.contains("今天是战略性休息"))
        #expect(try Self.english(for: "今天是战略性休息") == "Today is a strategic rest day")
        #expect(try Self.english(for: "周三不练腿俱乐部") != nil)
    }

    /// The care line's copy is the approved wording, and points at 988 and 911.
    @Test func careLineHasItsApprovedCopy() throws {
        #expect(try Self.english(for: "打给 988") == "Call 988")
        #expect(try Self.english(for: "发短信给 988") == "Text 988")
        #expect(try Self.english(for: "有紧急危险请直接打 911。") == "If you're in immediate danger, call 911.")
        let source = try String(
            contentsOf: Self.sources.appendingPathComponent("DisclaimerCard.swift"), encoding: .utf8)
        #expect(source.contains("\"tel:988\""))
        #expect(source.contains("\"sms:988\""))
    }

    /// SwiftLint's banned-terms rule can't read the catalog, so this covers its copy.
    @Test func catalogAvoidsBannedTerms() throws {
        let text = try String(contentsOf: Self.catalogURL, encoding: .utf8).lowercased()
        // Escaped, so the lint rule does not flag the test itself.
        for term in ["\u{5965}\u{8FD0}", "\u{6F}lympic"] {
            #expect(!text.contains(term), "the String Catalog uses a banned term")
        }
    }

    private static let catalogURL = sources.appendingPathComponent("Resources/Localizable.xcstrings")

    private static func english(for key: String) throws -> String? {
        try value(for: key, in: "en")
    }

    private static func value(for key: String, in language: String) throws -> String? {
        let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as? [String: Any]
        let entry = (catalog?["strings"] as? [String: Any])?[key] as? [String: Any]
        let localized = (entry?["localizations"] as? [String: Any])?[language] as? [String: Any]
        let value = (localized?["stringUnit"] as? [String: Any])?["value"] as? String
        return value?.isEmpty == false ? value : nil
    }

    /// Every key in `Text("…", bundle: .module)`, with each `\(…)` read as the `%lld` an `Int`
    /// interpolation becomes.
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
