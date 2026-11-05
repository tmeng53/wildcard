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

@Test func theThanksgivingOpeningSaysItInEachLanguage() throws {
    let opening = try #require(OpeningArt.load("trot")).opening
    let title = try #require(opening.layers.first { $0.id == "title" })
    guard case .text(let words, _, _, _) = title.content else {
        Issue.record("the title is words")
        return
    }
    #expect(words == ["zh-Hans": "感恩节快乐", "en": "Happy Thanksgiving", "zh-Hant": "感恩節快樂"])
}

@Test func anIdThatIsNotOneLoadsNothing() {
    #expect(OpeningArt.load("../Placeholder")?.opening == nil)
    #expect(OpeningArt.load("Trot")?.opening == nil)
    #expect(OpeningArt.load("")?.opening == nil)
    #expect(OpeningArt.load("newYear")?.opening == nil)
}
