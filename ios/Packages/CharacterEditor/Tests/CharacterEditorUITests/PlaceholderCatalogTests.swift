import AvatarArt
import AvatarDomain
import CharacterEditorDomain
import CharacterEditorUI
import Testing

/// The bundled art gives the editor what the design shows: five species, WARM-UP's twelve pieces,
/// two props, and swatches with a 原色 for exactly the pieces that recolor.
@Test func thePlaceholderCatalogComesFromTheArt() throws {
    let catalog = try Catalog.placeholder()
    #expect(catalog.species.map(\.id) == ["person", "cat", "dog", "rabbit", "bear"])
    #expect(catalog.props == ["dumbbell", "racket"])
    #expect(catalog.variants["top"] == ["warmup-tee", "warmup-tank", "warmup-hoodie"])
    #expect(catalog.variants["bottom"] == ["warmup-shorts", "warmup-joggers", "warmup-leggings"])
    #expect(catalog.variants["shoes"] == ["warmup-canvas", "warmup-runner"])
    #expect(catalog.variants["hat"] == ["warmup-cap", "warmup-headband"])
    #expect(catalog.variants["acc"] == ["warmup-towel", "warmup-waistbag"])
    #expect(catalog.swatches(for: "body", wearing: "peach").count == 7)
    #expect(catalog.swatches(for: "body", wearing: "calico").isEmpty)
    #expect(catalog.originals["top"]?["warmup-tee"] == RGBAColor(hex: "#F4F6FA"))
    for slot in Catalog.clothingSlots {
        for variant in catalog.variants[slot] ?? [] {
            #expect(catalog.swatches(for: slot, wearing: variant).count == 5, "\(variant)")
        }
    }
    #expect(catalog.variants["eyes"] == ["dot", "happy", "round", "sharp", "sleepy", "sparkle"])
    #expect(catalog.variants["brows"] == ["arched", "bold", "soft", "worried"])
    #expect(catalog.variants["mouth"] == ["cat", "grin", "oh", "smile", "smirk"])
    #expect(catalog.variants["cheeks"] == ["flushed", "freckles", "rosy"])
    #expect(catalog.variants["glasses"] == ["round", "square"])
    #expect(catalog.swatches(for: "eyes", wearing: "round").isEmpty == false)
    #expect(catalog.swatches(for: "brows", wearing: "soft") == catalog.swatches(for: "hair", wearing: "bob"))
    #expect(catalog.swatches["mouth"] == nil && catalog.swatches["cheeks"] == nil && catalog.swatches["glasses"] == nil)
    #expect(
        catalog.defaults == [
            "eyes": "round", "mouth": "smile", "top": "warmup-tee", "bottom": "warmup-shorts", "shoes": "warmup-canvas",
        ])
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
