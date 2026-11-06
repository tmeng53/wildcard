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
