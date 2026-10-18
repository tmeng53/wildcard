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
                "BarlowCondensed-Bold", "BarlowCondensed-ExtraBold", "BarlowCondensed-SemiBold",
            ])
    }

    @Test(arguments: [ScoreboardWeight.semibold, .bold, .extraBold])
    func everyScoreboardFaceResolvesToABundledFont(weight: ScoreboardWeight) {
        ScoreboardFont.register()
        let name = Face.scoreboard(weight).postScriptName
        let font = CTFontCreateWithName(name as CFString, 12, nil)
        // CoreText falls back to another font, silently, when a name is missing.
        #expect(CTFontCopyPostScriptName(font) as String == name)
    }
}

struct StringCatalogTests {
    @Test func styleGuideHasEnglish() throws {
        let path = try #require(Bundle.module.path(forResource: "en", ofType: "lproj"))
        let english = try #require(Bundle(path: path))
        #expect(english.localizedString(forKey: "开跑", value: nil, table: nil) == "Go")
        #expect(english.localizedString(forKey: "配色", value: nil, table: nil) == "Color")
    }
}
#endif
