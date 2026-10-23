import Foundation
import OnboardingDomain
import Testing

/// SwiftPM doesn't extract string keys, so a `Text` whose key is missing from the String Catalog
/// silently shows Chinese in English. This reads OnboardingUI's sources and catalog as files, so
/// it runs on Linux too.
struct StringCatalogCoverageTests {
    private static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let sources = packageRoot.appendingPathComponent("Sources/OnboardingUI")
    private static let catalogURL = sources.appendingPathComponent("Resources/Localizable.xcstrings")

    @Test func everyLocalizedTextHasAnEnglishEntry() throws {
        let keys = try Self.localizedKeys()
        #expect(keys.count > 20, "found only \(keys.count) keys; is the pattern still right?")
        // An `Int` interpolation's key holds `%lld`, a `String`'s holds `%@`.
        let missing = try keys.filter {
            try Self.value(for: $0, in: "en") == nil
                && Self.value(for: $0.replacingOccurrences(of: "%lld", with: "%@"), in: "en") == nil
        }
        #expect(missing.isEmpty, "not in the String Catalog with English: \(missing.sorted())")
    }

    /// The squad name 建一个小队 starts from, built with `String(localized:)`.
    @Test func suggestedSquadNameHasEnglish() throws {
        #expect(try Self.value(for: "%@ 的小队", in: "en") == "%@'s squad")
    }

    /// Every welcome line is in the catalog in Chinese and English, with the approved wording.
    @Test func everyWelcomeLineHasBothLanguages() throws {
        #expect(WelcomeLines.allKeys.count == 58)
        for key in WelcomeLines.allKeys {
            #expect(try Self.value(for: key, in: "zh-Hans") != nil, "\(key) has no Chinese")
            #expect(try Self.value(for: key, in: "en") != nil, "\(key) has no English")
        }
        #expect(try Self.value(for: "welcome.me.1", in: "zh-Hans") == "报到！")
        #expect(try Self.value(for: "welcome.drama.1", in: "zh-Hans") == "这一刻我等了一辈子")
        #expect(try Self.value(for: "welcome.showoff.10", in: "zh-Hans") == "入队仪式由我主持")
    }

    /// The bubbles stay one line on a phone, so a welcome line is short in every language.
    @Test func welcomeLinesAreShort() throws {
        for key in WelcomeLines.allKeys {
            let chinese = try #require(try Self.value(for: key, in: "zh-Hans"))
            let english = try #require(try Self.value(for: key, in: "en"))
            #expect(chinese.count <= 12, "\(chinese)")
            #expect(english.count <= 40, "\(english)")
        }
    }

    /// SwiftLint's banned-terms rule can't read the catalog, so this covers its copy.
    @Test func catalogAvoidsBannedTerms() throws {
        let text = try String(contentsOf: Self.catalogURL, encoding: .utf8).lowercased()
        // Escaped, so the lint rule does not flag the test itself.
        for term in ["\u{5965}\u{8FD0}", "\u{6F}lympic", "\u{5D3D}", "\u{5206}\u{8EAB}"] {
            #expect(!text.contains(term), "the String Catalog uses a banned term")
        }
    }

    private static func value(for key: String, in language: String) throws -> String? {
        let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as? [String: Any]
        let entry = (catalog?["strings"] as? [String: Any])?[key] as? [String: Any]
        let localized = (entry?["localizations"] as? [String: Any])?[language] as? [String: Any]
        let value = (localized?["stringUnit"] as? [String: Any])?["value"] as? String
        if value?.isEmpty == false { return value }
        // A key written in Chinese is its own Chinese.
        return language == "zh-Hans" && entry != nil && !key.hasPrefix("welcome.") ? key : nil
    }

    /// Every key in `Text("…", bundle: .module)`, with each `\(…)` read as `%lld`; the check also
    /// accepts the `%@` a `String` interpolation becomes.
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
