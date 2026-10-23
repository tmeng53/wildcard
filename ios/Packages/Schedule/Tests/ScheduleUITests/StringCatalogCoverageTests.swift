import Foundation
import ScheduleDomain
import Testing

@testable import ScheduleUI

/// SwiftPM doesn't extract string keys, so a `Text` whose key is missing from the String Catalog
/// silently shows Chinese in English. This reads ScheduleUI's sources and catalog as files, so
/// it runs on Linux too.
struct StringCatalogCoverageTests {
    private static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let sources = packageRoot.appendingPathComponent("Sources/ScheduleUI")
    private static let catalogURL = sources.appendingPathComponent("Resources/Localizable.xcstrings")

    @Test func everyLocalizedTextHasAnEnglishEntry() throws {
        let keys = try Self.localizedKeys()
        #expect(keys.count > 30, "found only \(keys.count) keys; is the pattern still right?")
        let missing = try keys.filter { try Self.englishForAnyPlaceholders($0) == nil }
        #expect(missing.isEmpty, "not in the String Catalog with English: \(missing.sorted())")
    }

    @Test func everyWeekdayAndFoodGoalHasBothLanguages() throws {
        for weekday in ["周一", "周二", "周三", "周四", "周五", "周六", "周日"] {
            #expect(try Self.value(for: weekday, in: "en") != nil, "\(weekday)")
        }
        for suggestion in FuelSuggestion.allCases {
            #expect(try Self.value(for: suggestion.key, in: "zh-Hans") != nil, "\(suggestion)")
            #expect(try Self.value(for: suggestion.key, in: "en") != nil, "\(suggestion)")
        }
        #expect(try Self.value(for: "fuel.water", in: "zh-Hans") == "喝够水")
    }

    /// A suggested goal fits where a goal of the member's own must.
    @Test func suggestedGoalsAreShortEnough() throws {
        for suggestion in FuelSuggestion.allCases {
            let words = try #require(try Self.value(for: suggestion.key, in: "zh-Hans"))
            #expect(words.count <= FuelGoal.maxLength, "\(words)")
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

    private static func value(for key: String, in language: String) throws -> String? {
        let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as? [String: Any]
        let entry = (catalog?["strings"] as? [String: Any])?[key] as? [String: Any]
        let localized = (entry?["localizations"] as? [String: Any])?[language] as? [String: Any]
        let value = (localized?["stringUnit"] as? [String: Any])?["value"] as? String
        return value?.isEmpty == false ? value : nil
    }

    /// An interpolated `Int` becomes `%lld` in the key, anything else `%@`; tries each mix.
    private static func englishForAnyPlaceholders(_ key: String) throws -> String? {
        let parts = key.components(separatedBy: placeholder)
        var candidates = [parts[0]]
        for part in parts.dropFirst() {
            candidates = candidates.flatMap { [$0 + "%lld" + part, $0 + "%@" + part] }
        }
        return try candidates.lazy.compactMap { try value(for: $0, in: "en") }.first
    }

    private static let placeholder = "\u{1}"

    /// Every key in `Text("…", bundle: .module)` and `String(localized: "…", bundle: .module)`,
    /// with each `\(…)` as a placeholder; nested parentheses inside it are skipped whole.
    private static func localizedKeys() throws -> Set<String> {
        let pattern = try NSRegularExpression(
            pattern: #"(?:Text|String)\((?:localized: )?"((?:[^"\\]|\\.)*)", bundle: \.module\)"#)
        let files = try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        var keys = Set<String>()
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(match.range(at: 1), in: text) else { continue }
                keys.insert(replacingInterpolations(String(text[range])))
            }
        }
        return keys
    }

    private static func replacingInterpolations(_ raw: String) -> String {
        var result = ""
        var characters = raw.makeIterator()
        while let character = characters.next() {
            guard character == "\\" else {
                result.append(character)
                continue
            }
            guard let next = characters.next(), next == "(" else { continue }
            var depth = 1
            while depth > 0, let inner = characters.next() {
                if inner == "(" { depth += 1 }
                if inner == ")" { depth -= 1 }
            }
            result += placeholder
        }
        return result
    }
}
