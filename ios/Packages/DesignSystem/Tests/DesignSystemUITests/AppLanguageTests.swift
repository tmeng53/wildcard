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

    @Test func anExtensionSpeaksTheLanguageTheAppShared() throws {
        let before = UserDefaults.standard.object(forKey: "AppleLanguages")
        defer { UserDefaults.standard.set(before, forKey: "AppleLanguages") }
        let suite = "AppLanguageTests.\(UUID().uuidString)"
        let shared = try #require(UserDefaults(suiteName: suite))
        defer { shared.removePersistentDomain(forName: suite) }
        UserDefaults.standard.set(["zh-Hans"], forKey: "AppleLanguages")

        // Nothing shared yet, or no shared settings: the extension keeps its own.
        AppLanguage.adopt(from: shared)
        AppLanguage.adopt(from: nil)
        #expect(AppLanguage.current == .simplifiedChinese)

        AppLanguage.english.share(in: shared)
        AppLanguage.adopt(from: shared)
        #expect(AppLanguage.current == .english)
        #expect(UserDefaults.standard.stringArray(forKey: "AppleLanguages") == ["en"])
    }

    @Test func eachLanguageIsNamedInItself() {
        #expect(AppLanguage.allCases.map(\.name) == ["简体中文", "English"])
        #expect(AppLanguage.english.locale.language.languageCode == .english)
    }
}
