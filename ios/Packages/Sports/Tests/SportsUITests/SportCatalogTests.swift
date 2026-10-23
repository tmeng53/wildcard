import Contracts
import Foundation
import Testing

/// SwiftPM doesn't extract string keys, so a sport whose key is missing from the String Catalog
/// silently shows its raw id. This reads SportsUI's catalog as a file, so it runs on Linux too.
struct SportCatalogTests {
    private static let catalogURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/SportsUI/Resources/Localizable.xcstrings")

    @Test func everySportAndCategoryHasANameInEveryLanguage() throws {
        let keys =
            Sport.allCases.map { "sport.\($0.rawValue)" }
            + SportCategory.allCases.map { "sportCategory.\($0.rawValue)" }
        #expect(keys.count == 64)
        let missing = try keys.filter {
            try Self.value(for: $0, in: "en") == nil || Self.value(for: $0, in: "zh-Hans") == nil
                || Self.value(for: $0, in: "zh-Hant") == nil
        }
        #expect(missing.isEmpty, "sports without a name in every language: \(missing)")
        #expect(try Self.value(for: "sport.pickleball", in: "zh-Hans") == "匹克球")
        #expect(try Self.value(for: "sport.tableTennis", in: "zh-Hant") == "桌球")
        #expect(try Self.value(for: "sportCategory.everyday", in: "en") == "Everyday counts")
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
}
