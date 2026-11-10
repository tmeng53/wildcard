import Contracts
import Foundation
import Testing

@testable import DesignSystemUI

// One suite, run in order: the copy installed is the whole process's.
extension TheAppsLanguage {
    @Suite struct AppCopyLinesTests {
        /// A bundle with a catalog, as a package's is once built: `zh-Hans.lproj/Localizable.strings`.
        private static func catalog(_ lines: [String: String]) throws -> Bundle {
            let root = FileManager.default.temporaryDirectory.appending(path: "AppCopyCatalog/\(UUID().uuidString)")
            let folder = root.appending(path: "zh-Hans.lproj")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: lines, format: .xml, options: 0)
            try data.write(to: folder.appending(path: "Localizable.strings"))
            return try #require(Bundle(url: root))
        }

        @Test func putsTheLinesPutInFrontOfTheCatalogs() throws {
            AppLanguage.simplifiedChinese.pick()
            let catalog = try Self.catalog(["练了": "练了", "商店街": "商店街"])
            AppCopyLines.install(
                AppCopy(entries: ["练了": AppCopy.Words(simplifiedChinese: "训练"), "商店街": AppCopy.Words(english: "Shops")])
            )

            #expect(String(copyKey: "练了", bundle: catalog) == "训练")
            // Put only in English: Chinese keeps the catalog's.
            #expect(String(copyKey: "商店街", bundle: catalog) == "商店街")
        }

        /// A built catalog whose source is Simplified Chinese: Xcode writes only the other
        /// languages' tables, since every Chinese line is its key.
        private static func sourceCatalog(english lines: [String: String]) throws -> Bundle {
            let root = FileManager.default.temporaryDirectory.appending(path: "AppCopyCatalog/\(UUID().uuidString)")
            let folder = root.appending(path: "en.lproj")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let info = try PropertyListSerialization.data(
                fromPropertyList: ["CFBundleDevelopmentRegion": "zh-Hans"], format: .xml, options: 0)
            try info.write(to: root.appending(path: "Info.plist"))
            let data = try PropertyListSerialization.data(fromPropertyList: lines, format: .xml, options: 0)
            try data.write(to: folder.appending(path: "Localizable.strings"))
            return try #require(Bundle(url: root))
        }

        #if canImport(Darwin)
        /// A plural line, as Xcode builds a String Catalog's plural variations: a stringsdict.
        @Test func fillsAPluralLineByItsCount() throws {
            let root = FileManager.default.temporaryDirectory.appending(path: "AppCopyCatalog/\(UUID().uuidString)")
            let folder = root.appending(path: "en.lproj")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let info = try PropertyListSerialization.data(
                fromPropertyList: ["CFBundleDevelopmentRegion": "zh-Hans"], format: .xml, options: 0)
            try info.write(to: root.appending(path: "Info.plist"))
            let plural: [String: Any] = [
                "%lld 天": [
                    "NSStringLocalizedFormatKey": "%#@days@",
                    "days": [
                        "NSStringFormatSpecTypeKey": "NSStringPluralRuleType", "NSStringFormatValueTypeKey": "lld",
                        "one": "%lld day", "other": "%lld days",
                    ] as [String: String],
                ] as [String: Any]
            ]
            let data = try PropertyListSerialization.data(fromPropertyList: plural, format: .xml, options: 0)
            try data.write(to: folder.appending(path: "Localizable.stringsdict"))
            let catalog = try #require(Bundle(url: root))
            AppCopyLines.install(.none)
            AppLanguage.english.pick()
            #expect(String(copy: "\(1) 天", bundle: catalog) == "1 day")
            #expect(String(copy: "\(3) 天", bundle: catalog) == "3 days")
            AppLanguage.simplifiedChinese.pick()
        }
        #endif

        @Test func speaksTheSourceLanguageWhereItHasNoTable() throws {
            let catalog = try Self.sourceCatalog(english: ["本周小队已练": "Squad this week"])
            AppCopyLines.install(.none)
            // The process may speak English (an extension speaks the phone's language): the app's
            // Chinese still reads as the key.
            AppLanguage.adopt(from: nil, folder: nil)
            UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
            #expect(String(copyKey: "本周小队已练", bundle: catalog) == "本周小队已练")
            AppLanguage.english.pick()
            #expect(String(copyKey: "本周小队已练", bundle: catalog) == "Squad this week")
            AppLanguage.simplifiedChinese.pick()
        }

        @Test func keepsTheCatalogsWordsWithNothingPut() throws {
            AppLanguage.simplifiedChinese.pick()
            let catalog = try Self.catalog(["练了": "练了"])
            AppCopyLines.install(.none)

            #expect(String(copyKey: "练了", bundle: catalog) == "练了")
            #expect(String(copyKey: "没有的", bundle: catalog) == "没有的")
        }

        @Test func fillsTheLinesPutWithTheirArguments() throws {
            AppLanguage.simplifiedChinese.pick()
            let catalog = try Self.catalog(["练了": "练了", "还有 %lld 次开门": "还有 %lld 次开门", "商店街": "商店街"])
            AppCopyLines.install(
                AppCopy(entries: [
                    "练了": AppCopy.Words(simplifiedChinese: "训练"),
                    "还有 %lld 次开门": AppCopy.Words(simplifiedChinese: "再练 %lld 次就开门"),
                    "商店街": AppCopy.Words(english: "Shops"),
                ]))

            #expect(String(copy: "练了", bundle: catalog) == "训练")
            let toGo = 2
            #expect(String(copy: "还有 \(toGo) 次开门", bundle: catalog) == "再练 2 次就开门")
            // Put only in English: Chinese keeps the catalog's.
            #expect(String(copy: "商店街", bundle: catalog) == "商店街")
            #expect(String(copyKey: "练了", bundle: catalog) == "训练")
            // The key Text would look up: a `%` written in a line with arguments is `%%`.
            let done: CopyLine = "\(toGo)% 完成"
            let whole: CopyLine = "100% 完成"
            #expect(done.key == "%lld%% 完成")
            #expect(whole.key == "100% 完成")
        }

        @Test func readsAFormatInItsParts() {
            #expect(
                CopyLine.pieces(of: "%@ 回复 %@：100%%")
                    == [
                        .argument(index: 0, conversion: "@"), .words(" 回复 "), .argument(index: 1, conversion: "@"),
                        .words("：100%"),
                    ])
            #expect(
                CopyLine.pieces(of: "%2$lld minutes for %1$@")
                    == [
                        .argument(index: 1, conversion: "lld"), .words(" minutes for "),
                        .argument(index: 0, conversion: "@"),
                    ])
        }

        @Test func passesOverALineThatDoesntFillLikeItsKey() throws {
            AppLanguage.simplifiedChinese.pick()
            let catalog = try Self.catalog(["还有 %lld 次开门": "还有 %lld 次开门"])
            AppCopyLines.install(AppCopy(entries: ["还有 %lld 次开门": AppCopy.Words(simplifiedChinese: "快开门了 %@")]))

            let toGo = 3
            #expect(String(copy: "还有 \(toGo) 次开门", bundle: catalog) == "还有 3 次开门")
        }
    }
}
