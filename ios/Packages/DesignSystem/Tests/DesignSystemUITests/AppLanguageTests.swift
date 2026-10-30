import DesignSystemUI
import Foundation
import Testing

/// The app's language, as `AppleLanguages` records it. These change the test process's own
/// defaults, so they run one at a time and put them back.
@Suite(.serialized)
struct AppLanguageTests {
    @Test func aPickIsSpokenAtOnceAndRecordedForTheNextLaunch() {
        let before = UserDefaults.standard.object(forKey: "AppleLanguages")
        defer { UserDefaults.standard.set(before, forKey: "AppleLanguages") }
        AppLanguage.english.pick()
        #expect(AppLanguage.current == .english)
        #expect(UserDefaults.standard.stringArray(forKey: "AppleLanguages") == ["en"])
        AppLanguage.simplifiedChinese.pick()
        #expect(AppLanguage.current == .simplifiedChinese)
    }

    @Test func aLanguageTheAppDoesntSpeakFallsToOneItDoes() {
        let before = UserDefaults.standard.object(forKey: "AppleLanguages")
        defer { UserDefaults.standard.set(before, forKey: "AppleLanguages") }
        UserDefaults.standard.set(["en-US", "fr"], forKey: "AppleLanguages")
        #expect(AppLanguage.current == .english)
        UserDefaults.standard.set(["zh-Hans-CN"], forKey: "AppleLanguages")
        #expect(AppLanguage.current == .simplifiedChinese)
    }

    @Test func eachLanguageIsNamedInItself() {
        #expect(AppLanguage.allCases.map(\.name) == ["简体中文", "English"])
        #expect(AppLanguage.english.locale.language.languageCode == .english)
    }
}
