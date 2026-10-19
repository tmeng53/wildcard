import AvatarArt
import AvatarDomain
import CharacterEditorDomain
import CharacterEditorUI
import Testing

/// The bundled art gives the editor what the design shows: five species, two props, and swatches
/// with a 原色 for exactly the pieces that recolor.
@Test func thePlaceholderCatalogComesFromTheArt() throws {
    let catalog = try Catalog.placeholder()
    #expect(catalog.species.map(\.id) == ["person", "cat", "dog", "rabbit", "bear"])
    #expect(catalog.props == ["dumbbell", "racket"])
    #expect(catalog.variants["hat"] == ["cap", "headband"])
    #expect(catalog.swatches(for: "body", wearing: "peach").count == 7)
    #expect(catalog.swatches(for: "body", wearing: "calico").isEmpty)
    #expect(catalog.originals["top"]?["tee"] == RGBAColor(hex: "#2D5BA0"))
    #expect(catalog.swatches["hat"] == nil)
    for (slot, byVariant) in catalog.swatches {
        #expect(Set(byVariant.keys) == Set(catalog.originals[slot].map { Array($0.keys) } ?? []))
    }
}

/// Every random look the editor can start from is one the art can draw.
@Test func randomLooksBuild() throws {
    let catalog = try Catalog.placeholder()
    var generator = SystemRandomNumberGenerator()
    for _ in 0..<40 {
        let look = CharacterDraft.randomLook(from: catalog, using: &generator)
        var draft = CharacterDraft(catalog: catalog, look: look, persona: .deadpan, nickname: "")
        _ = try PlaceholderCharacter.figure(wearing: draft.outfit)
        draft.pick("bear", for: "body")
        _ = try PlaceholderCharacter.figure(wearing: draft.outfit)
    }
}
