import Contracts
import Testing

struct AppCopyTests {
    @Test func readsSwiftsInterpolationsAndExplicitPositions() {
        #expect(AppCopy.formatArguments("%@ 练了 %lld 分钟，%lf 公里") == [1: "@", 2: "lld", 3: "lf"])
        #expect(AppCopy.formatArguments("%2$lld minutes by %1$@") == [2: "lld", 1: "@"])
        #expect(AppCopy.formatArguments("100%% 完成").isEmpty)
    }

    @Test func takesWordsThatFillLikeTheKey() {
        #expect(AppCopy.fillsLike(key: "还有 %lld 次开门", words: "再练 %lld 次就开门"))
        #expect(AppCopy.fillsLike(key: "%@ 练了 %lld 分钟", words: "%2$lld minutes for %1$@"))
        #expect(!AppCopy.fillsLike(key: "还有 %lld 次开门", words: "快开门了"))
        #expect(!AppCopy.fillsLike(key: "商店街", words: "%@ 的商店街"))
        #expect(!AppCopy.fillsLike(key: "还有 %lld 次开门", words: "还有 %@ 次开门"))
    }

    @Test func givesTheWordsInTheAppsLanguageOnlyWhenTheyFill() {
        let copy = AppCopy(entries: [
            "练了": AppCopy.Words(simplifiedChinese: "训练", english: "Trained"),
            "还有 %lld 次开门": AppCopy.Words(simplifiedChinese: "快开门了"),
        ])
        #expect(copy.words(for: "练了", in: "zh-Hans") == "训练")
        #expect(copy.words(for: "练了", in: "en") == "Trained")
        #expect(copy.words(for: "练了", in: "zh-Hant") == nil)
        #expect(copy.words(for: "还有 %lld 次开门", in: "zh-Hans") == nil)
        #expect(copy.words(for: "商店街", in: "zh-Hans") == nil)
    }
}
