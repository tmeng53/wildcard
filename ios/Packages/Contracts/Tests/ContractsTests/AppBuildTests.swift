import Contracts
import Testing

@Suite("The lowest build that may run")
struct AppBuildTests {
    @Test("reads the build numbers TestFlight gives, and nothing else")
    func reads() {
        #expect(AppBuild("190")?.description == "190")
        #expect(AppBuild("186.1")?.description == "186.1")
        #expect(AppBuild("190.0")?.description == "190")
        #expect(AppBuild("1.2.3")?.description == "1.2.3")
        #expect(AppBuild("") == nil)
        #expect(AppBuild("190.") == nil)
        #expect(AppBuild("v190") == nil)
        #expect(AppBuild("1.2.3.4") == nil)
        #expect(AppBuild("-1") == nil)
    }

    @Test("compares number by number")
    func compares() throws {
        let build = try #require(AppBuild("186.1"))
        #expect(build.mayRun(withMinimum: nil))
        #expect(build.mayRun(withMinimum: AppBuild("186")))
        #expect(build.mayRun(withMinimum: AppBuild("186.1")))
        #expect(!build.mayRun(withMinimum: AppBuild("186.2")))
        #expect(!build.mayRun(withMinimum: AppBuild("190")))
        #expect(try #require(AppBuild("190.2")) < #require(AppBuild("190.10")))
        #expect(AppBuild("190.0") == AppBuild("190"))
    }

    @Test("the quick reactions keep the shipped bar until the catalog names some")
    func quickReactions() throws {
        let reactions = QuickReactions()
        #expect(reactions.emoji.map(\.text) == ["❤️", "💪", "😂", "🤤", "😮", "😡"])
        reactions.show([try Emoji("🔥"), try Emoji("👏")])
        #expect(reactions.emoji.map(\.text) == ["🔥", "👏"])
        reactions.show([])
        #expect(reactions.emoji.count == 6)
    }
}
