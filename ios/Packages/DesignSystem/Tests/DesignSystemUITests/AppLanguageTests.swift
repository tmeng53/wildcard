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
        AppLanguage.traditionalChinese.pick()
        #expect(AppLanguage.current == .traditionalChinese)
        #expect(UserDefaults.standard.stringArray(forKey: "AppleLanguages") == ["zh-Hant"])
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
        UserDefaults.standard.set(["zh-Hant-TW"], forKey: "AppleLanguages")
        #expect(AppLanguage.current == .traditionalChinese)
        UserDefaults.standard.set(["zh-HK", "en"], forKey: "AppleLanguages")
        #expect(AppLanguage.current == .traditionalChinese)
        UserDefaults.standard.set(["zh-CN"], forKey: "AppleLanguages")
        #expect(AppLanguage.current == .simplifiedChinese)
    }

    @Test func anExtensionSpeaksTheLanguageTheAppShared() throws {
        let before = UserDefaults.standard.object(forKey: "AppleLanguages")
        defer { UserDefaults.standard.set(before, forKey: "AppleLanguages") }
        let suite = "AppLanguageTests.\(UUID().uuidString)"
        let shared = try #require(UserDefaults(suiteName: suite))
        defer { shared.removePersistentDomain(forName: suite) }
        let folder = FileManager.default.temporaryDirectory.appending(path: suite)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        UserDefaults.standard.set(["en"], forKey: "AppleLanguages")

        // Nothing shared yet, or nowhere to share it: the extension speaks the app's first language.
        AppLanguage.adopt(from: shared, folder: folder)
        #expect(AppLanguage.current == .simplifiedChinese)
        UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
        AppLanguage.adopt(from: nil, folder: nil)
        #expect(AppLanguage.current == .simplifiedChinese)

        AppLanguage.english.share(in: shared, folder: folder)
        AppLanguage.adopt(from: shared, folder: folder)
        #expect(AppLanguage.current == .english)
        #expect(UserDefaults.standard.stringArray(forKey: "AppleLanguages") == ["en"])

        // The shared folder's file wins over the shared settings, and either works alone.
        AppLanguage.traditionalChinese.share(in: nil, folder: folder)
        AppLanguage.adopt(from: shared, folder: folder)
        #expect(AppLanguage.current == .traditionalChinese)
        AppLanguage.adopt(from: shared, folder: nil)
        #expect(AppLanguage.current == .english)
    }

    @Test func eachLanguageIsNamedInItself() {
        #expect(AppLanguage.allCases.map(\.name) == ["简体中文", "繁體中文", "English"])
        #expect(AppLanguage.traditionalChinese.locale.language.script == .hanTraditional)
        #expect(AppLanguage.english.locale.language.languageCode == .english)
    }
}
