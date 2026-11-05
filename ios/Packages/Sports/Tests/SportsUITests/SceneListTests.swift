import Contracts
import DesignSystem
import SportsUI
import Testing

// A scene added through the admin tools after this build shipped (TURKEY TROT's `trot`) is
// named and coloured as the catalog says, and drawn in code as the gym.

private func scene(_ id: String, signature: String = "#B5532A") -> CatalogScene? {
    SceneID(rawValue: id).map {
        CatalogScene(
            id: $0,
            names: CatalogNames(simplifiedChinese: "火鸡大道", english: "Turkey Trot", traditionalChinese: "火雞大道"),
            colors: .init(
                signature: signature, onSignature: "#FFFFFF", wash: "#FBEDE5", text: "#8A3B1A", floor: "#F3DCCD"))
    }
}

@Test func aSceneAddedSinceTakesTheCatalogsWords() throws {
    SceneTheme.list([try #require(scene("trot")), try #require(scene("gym", signature: "#000000"))])
    defer { SceneTheme.list([]) }

    let trot = try #require(SceneTheme(rawValue: "trot"))
    #expect(trot.base == .gym)
    #expect(trot.colors.accent.hex == "#B5532A")
    #expect(trot.colors.floor.hex == "#F3DCCD")
    #expect(SceneTheme.listing(trot)?.english == "Turkey Trot")
    // A scene this build was made with keeps the design's tokens.
    #expect(SceneTheme.gym.colors.accent.hex == "#4A6C8C")
    #expect(SceneTheme.gym.base == .gym)
}

@Test func aSceneNobodyListedShowsAsTheGym() throws {
    let jingle = try #require(SceneTheme(rawValue: "jingle"))
    #expect(jingle.colors == SceneTheme.gym.colors)
    #expect(SceneTheme(rawValue: "Jingle") == nil)
    #expect(SceneTheme(rawValue: "jingle-jog") == nil)
}
