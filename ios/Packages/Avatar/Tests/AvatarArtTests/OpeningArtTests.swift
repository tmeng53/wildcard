import AvatarDomain
import Testing

@testable import AvatarArt

// The holiday openings this build bundles play, each with every layer's art, and an id that
// isn't one is never read as a path.

@Test(arguments: ["trot", "jingle"])
func aBundledOpeningLoadsWithAllItsArt(id: String) throws {
    let loaded = try #require(OpeningArt.load(id))
    #expect(Set(loaded.art.keys) == Set(loaded.opening.artFiles))
    #expect(loaded.opening.layers.contains { $0.content == .squad })
    #expect(loaded.opening.clip.duration == 3)
}

// A letter from Wildcard to the squad (Tracy, 2026-11-06): 「<squad>，」 / 「感恩节快乐！」 / 「— 外卡」.
@Test func theThanksgivingOpeningIsALetterToTheSquad() throws {
    let opening = try #require(OpeningArt.load("trot")).opening
    func line(_ id: PartID, _ language: String) throws -> String {
        let layer = try #require(opening.layers.first { $0.id == id })
        guard case .text(let words, _, _, _) = layer.content else { return "" }
        return Opening.words(words, language: language, squad: "快乐小队")
    }
    #expect(try ["to", "title", "from"].map { try line($0, "zh-Hans") } == ["快乐小队，", "感恩节快乐！", "— 外卡"])
    #expect(try ["to", "title", "from"].map { try line($0, "en") } == ["快乐小队,", "Happy Thanksgiving!", "— Wildcard"])
    #expect(try ["to", "title", "from"].map { try line($0, "zh-Hant") } == ["快乐小队，", "感恩節快樂！", "— 外卡"])
}

@Test func anIdThatIsNotOneLoadsNothing() {
    #expect(OpeningArt.load("../Placeholder")?.opening == nil)
    #expect(OpeningArt.load("Trot")?.opening == nil)
    #expect(OpeningArt.load("")?.opening == nil)
    #expect(OpeningArt.load("newYear")?.opening == nil)
}
