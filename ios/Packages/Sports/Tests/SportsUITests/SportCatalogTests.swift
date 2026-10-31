import Contracts
import Foundation
import SportsUI
import Testing

/// SwiftPM doesn't extract string keys, so this reads SportsUI's String Catalog as a file, so it
/// runs on Linux too. Sports' own names are data the API serves, not in the catalog.
struct SportCatalogTests {
    private static let catalogURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/SportsUI/Resources/Localizable.xcstrings")

    @Test func aSportTheListDoesNotHaveYetHasAChineseAndEnglishName() throws {
        #expect(try Self.value(for: "sport.unknown", in: "zh-Hans") == "运动")
        #expect(try Self.value(for: "sport.unknown", in: "en") == "Workout")
    }

    /// SwiftLint's banned-terms rule can't read the catalog, so this covers its copy.
    @Test func catalogAvoidsBannedTerms() throws {
        let text = try String(contentsOf: Self.catalogURL, encoding: .utf8).lowercased()
        // Escaped, so the lint rule does not flag the test itself.
        for term in ["\u{5965}\u{8FD0}", "\u{6F}lympic"] {
            #expect(!text.contains(term), "the String Catalog uses a banned term")
        }
    }

    @Test func namesFollowTheAppsLanguage() {
        let names = CatalogNames(simplifiedChinese: "羽毛球", english: "Badminton", traditionalChinese: "羽球")
        #expect(names.localized(in: ["zh-Hans"]) == "羽毛球")
        #expect(names.localized(in: ["zh-Hant"]) == "羽球")
        #expect(names.localized(in: ["zh-Hant-TW"]) == "羽球")
        #expect(names.localized(in: ["en"]) == "Badminton")
        #expect(names.localized(in: ["en-US"]) == "Badminton")
        #expect(names.localized(in: ["fr", "en"]) == "Badminton")
        #expect(names.localized(in: ["fr"]) == "羽毛球")
    }

    @Test func theAppsListChangesWhenANewerOneArrives() {
        let list = SportList.shared
        let catalog = SportCatalog(
            categories: [
                SportCatalog.Category(
                    id: "racket",
                    names: CatalogNames(simplifiedChinese: "球拍", english: "Racket", traditionalChinese: "球拍"),
                    entries: [
                        SportCatalog.Entry(
                            sport: "padel",
                            names: CatalogNames(
                                simplifiedChinese: "板式网球", english: "Padel", traditionalChinese: "板式網球"),
                            icon: "figure.tennis", offered: true, category: "racket")
                    ])
            ], signUpCommon: [], checkInQuick: ["padel"])
        list.show(catalog)
        #expect(list.catalog.checkInQuick == ["padel"])
        list.show(.empty)
        #expect(list.catalog == .empty)
    }

    private static func value(for key: String, in language: String) throws -> String? {
        let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as? [String: Any]
        let entry = (catalog?["strings"] as? [String: Any])?[key] as? [String: Any]
        let localized = (entry?["localizations"] as? [String: Any])?[language] as? [String: Any]
        let value = (localized?["stringUnit"] as? [String: Any])?["value"] as? String
        return value?.isEmpty == false ? value : nil
    }
}
