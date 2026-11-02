import Foundation
import SquadDomain
import Testing

@testable import SquadUI

/// SwiftPM doesn't extract string keys, so a `Text` whose key is missing from the String Catalog
/// silently shows Chinese in English. This reads SquadUI's sources and catalog as files, so it
/// runs on Linux too.
struct StringCatalogCoverageTests {
    private static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let sources = packageRoot.appendingPathComponent("Sources/SquadUI")
    private static let catalogURL = sources.appendingPathComponent("Resources/Localizable.xcstrings")

    @Test func everyLocalizedTextHasAnEnglishEntry() throws {
        let keys = try Self.localizedKeys()
        #expect(keys.count > 30, "found only \(keys.count) keys; is the pattern still right?")
        let english = try Self.englishKeys()
        let missing = try keys.filter { key in
            let pattern = try NSRegularExpression(
                pattern: "^"
                    + NSRegularExpression.escapedPattern(for: key).replacingOccurrences(
                        of: "\u{1}", with: "(%lld|%@)") + "$")
            return !english.contains { pattern.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil }
        }
        #expect(missing.isEmpty, "not in the String Catalog with English: \(missing.sorted())")
    }

    /// The sample squad's names come from the catalog too.
    @Test func sampleNamesHaveEnglish() throws {
        let english = try Self.englishKeys()
        for name in ["小林", "阿杰", "大卫", "晨跑五人组"] { #expect(english.contains(name)) }
    }

    /// SwiftLint's banned-terms rule can't read the catalog, so this covers its copy.
    @Test func catalogAvoidsBannedTerms() throws {
        let text = try String(contentsOf: Self.catalogURL, encoding: .utf8).lowercased()
        // Escaped, so the lint rule does not flag the test itself.
        for term in ["\u{5965}\u{8FD0}", "\u{6F}lympic"] {
            #expect(!text.contains(term), "the String Catalog uses a banned term")
        }
    }

    /// The catalog's keys that have an English value, or English plural forms.
    private static func englishKeys() throws -> Set<String> {
        let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as? [String: Any]
        let strings = catalog?["strings"] as? [String: Any] ?? [:]
        return Set(
            strings.compactMap { key, entry in
                let localized = ((entry as? [String: Any])?["localizations"] as? [String: Any])?["en"] as? [String: Any]
                // A plural's English is its `other` form.
                let plural = (localized?["variations"] as? [String: Any])?["plural"] as? [String: Any]
                let unit = localized?["stringUnit"] ?? (plural?["other"] as? [String: Any])?["stringUnit"]
                let value = (unit as? [String: Any])?["value"] as? String
                return value?.isEmpty == false ? key : nil
            })
    }

    /// Every key in `Text("…", bundle: .module)` and `String(localized: "…", bundle: .module)`,
    /// with each `\(…)` marked, to match the `%lld` or `%@` it becomes.
    private static func localizedKeys() throws -> Set<String> {
        let pattern = try NSRegularExpression(
            pattern: #"(?:Text|String)\(\s*(?:localized:\s*)?"((?:[^"\\]|\\.)*)",\s*bundle: \.module\)"#)
        let interpolation = try NSRegularExpression(pattern: #"\\\((?:[^()]|\([^()]*\))*\)"#)
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
                        in: raw, range: NSRange(raw.startIndex..., in: raw), withTemplate: "\u{1}"))
            }
        }
        return keys
    }
}

struct InMemorySquadSettingsServiceTests {
    @MainActor @Test func theSampleCaptainManagesAndTheWinnerPicks() async {
        let captain = SquadSettingsModel(service: InMemorySquadSettingsService.sample(seat: .captain))
        await captain.reload()
        #expect(captain.isCaptain)
        #expect(captain.members.count == 5)
        #expect(!captain.canPickScene)
        let winner = SquadSettingsModel(service: InMemorySquadSettingsService.sample(seat: .winner))
        await winner.reload()
        #expect(winner.canPickScene)
        #expect(winner.sceneLine == .youWon)
        await winner.leave()
        #expect(winner.hasLeft)
    }
}
