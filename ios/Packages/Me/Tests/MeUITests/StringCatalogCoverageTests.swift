import Foundation
import MeDomain
import Testing

@testable import MeUI

/// SwiftPM doesn't extract string keys, so a `Text` whose key is missing from the String Catalog
/// silently shows Chinese in English. This reads MeUI's sources and catalog as files, so it runs
/// on Linux too.
struct StringCatalogCoverageTests {
    private static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let sources = packageRoot.appendingPathComponent("Sources/MeUI")
    private static let catalogURL = sources.appendingPathComponent("Resources/Localizable.xcstrings")

    @Test func everyLocalizedTextHasAnEnglishEntry() throws {
        let keys = try Self.localizedKeys()
        #expect(keys.count > 20, "found only \(keys.count) keys; is the pattern still right?")
        let missing = try keys.filter {
            try Self.english(for: $0) == nil
                && Self.english(for: $0.replacingOccurrences(of: "%lld", with: "%@")) == nil
        }
        #expect(missing.isEmpty, "not in the String Catalog with English: \(missing.sorted())")
    }

    /// The sample member's names come from the catalog too.
    @Test func sampleNamesHaveEnglish() throws {
        #expect(try Self.english(for: "小林") == "Lin")
        #expect(try Self.english(for: "周三不练腿俱乐部") == "Skip Leg Day Club")
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
        try value(for: key, in: "en")
    }

    private static func value(for key: String, in language: String) throws -> String? {
        let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as? [String: Any]
        let entry = (catalog?["strings"] as? [String: Any])?[key] as? [String: Any]
        let localized = (entry?["localizations"] as? [String: Any])?[language] as? [String: Any]
        let value = (localized?["stringUnit"] as? [String: Any])?["value"] as? String
        return value?.isEmpty == false ? value : nil
    }

    /// Every key in `Text("…", bundle: .module)`, with each `\(…)` read as `%lld`; the check also
    /// accepts the `%@` a `String` interpolation becomes.
    private static func localizedKeys() throws -> Set<String> {
        let pattern = try NSRegularExpression(pattern: #"Text\(\s*"((?:[^"\\]|\\.)*)",\s*bundle: \.module\)"#)
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

struct InMemoryMeServiceTests {
    @Test func remembersWhatIsSavedAndRefusesWhenToldTo() async throws {
        let service = InMemoryMeService.sample()
        try await service.setDailyPush(false)
        #expect(try await service.overview().dailyPushOn == false)
        #expect(try await service.overview().counts.trainedDays == 128)

        let failing = InMemoryMeService.sample(failsSaving: true)
        await #expect(throws: MeError.unavailable) { try await failing.setDailyPush(false) }
        #expect(try await failing.overview().dailyPushOn == true)
    }
}
