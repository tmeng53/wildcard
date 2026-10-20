#if canImport(SwiftUI)
import CoreText
import DesignSystem
@testable import DesignSystemUI
import Foundation
import Testing

struct ScoreboardFontTests {
    @Test func bundledCutsRegisterUnderTheirFaceNames() {
        ScoreboardFont.register()
        #expect(
            ScoreboardFont.registeredNames == [
                "BarlowCondensed-ExtraBold", "BarlowCondensed-SemiBold",
            ])
    }

    @Test(arguments: [ScoreboardWeight.semibold, .extraBold])
    func everyScoreboardFaceResolvesToABundledFont(weight: ScoreboardWeight) {
        ScoreboardFont.register()
        let name = Face.scoreboard(weight).postScriptName
        let font = CTFontCreateWithName(name as CFString, 12, nil)
        // CoreText falls back to another font, silently, when a name is missing.
        #expect(CTFontCopyPostScriptName(font) as String == name)
    }
}

struct StringCatalogTests {
    /// Command-line SwiftPM copies the catalog as is; Xcode compiles it into `.lproj` tables.
    /// The UI test launching the app in English checks the compiled form.
    @Test func everyStyleGuideStringHasEnglish() throws {
        let url = try #require(Bundle.module.url(forResource: "Localizable", withExtension: "xcstrings"))
        let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
        #expect(catalog.sourceLanguage == "zh-Hans")
        #expect(catalog.strings["下一步"]?.localizations["en"]?.stringUnit.value == "Next")
        #expect(catalog.strings["打卡"]?.localizations["en"]?.stringUnit.value == "Check in")
        #expect(catalog.strings["坦白放纵餐"]?.localizations["en"]?.stringUnit.value == "Cheat meal confession")
        let missing = catalog.strings.filter { $0.value.localizations["en"]?.stringUnit.value.isEmpty ?? true }
        #expect(missing.isEmpty, "no English for \(missing.keys.sorted())")
    }
}

private struct Catalog: Decodable {
    let sourceLanguage: String
    let strings: [String: CatalogEntry]
}

private struct CatalogEntry: Decodable {
    let localizations: [String: CatalogLocalization]
}

private struct CatalogLocalization: Decodable {
    let stringUnit: CatalogStringUnit
}

private struct CatalogStringUnit: Decodable {
    let value: String
}
#endif
