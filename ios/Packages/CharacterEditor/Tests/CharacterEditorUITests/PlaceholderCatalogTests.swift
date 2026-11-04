import AvatarArt
import AvatarDomain
import CharacterEditorDomain
import CharacterEditorUI
import Contracts
import Foundation
import Testing

/// The bundled art gives the editor what the design shows: five species, WARM-UP's nineteen pieces,
/// the two props every member starts with, and swatches with a 原色 for exactly the pieces that recolor.
@Test func thePlaceholderCatalogComesFromTheArt() throws {
    let catalog = try Catalog.placeholder()
    #expect(catalog.species.map(\.id) == ["person", "cat", "dog", "rabbit", "bear"])
    #expect(catalog.props == ["bottle", "dumbbell"])
    #expect(
        catalog.variants["top"] == [
            "warmup-tee", "warmup-tank", "warmup-hoodie", "warmup-long", "warmup-raglan", "warmup-stripe",
        ])
    #expect(catalog.variants["bottom"] == ["warmup-shorts", "warmup-joggers", "warmup-leggings", "warmup-overalls"])
    #expect(catalog.variants["shoes"] == ["warmup-canvas", "warmup-runner", "warmup-hightop"])
    #expect(catalog.variants["hat"] == ["warmup-cap", "warmup-headband", "warmup-beanie", "warmup-headphones"])
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

/// The shopping street: six stores, WARM-UP open at the start, and every piece of clothing on
/// a rack, WARM-UP's nineteen pieces, tops first, then bottoms, shoes, hats and accessories.
@Test func everyPieceHangsInAStore() throws {
    let catalog = try Catalog.placeholder()
    #expect(catalog.stores.map(\.id) == ["warmup", "lap", "nolook", "moss", "halfmoon", "deuce"])
    #expect(catalog.stores.filter(\.isOpen).map(\.id) == ["warmup"])
    #expect(
        catalog.rack(of: "warmup").map(\.variant) == [
            "warmup-tee", "warmup-tank", "warmup-hoodie", "warmup-long", "warmup-raglan", "warmup-stripe",
            "warmup-shorts", "warmup-joggers", "warmup-leggings", "warmup-overalls", "warmup-canvas", "warmup-runner",
            "warmup-hightop", "warmup-cap", "warmup-headband", "warmup-beanie", "warmup-headphones", "warmup-towel",
            "warmup-waistbag",
        ])
    let racked = catalog.stores.flatMap { catalog.rack(of: $0.id).map(\.variant) }
    #expect(Set(racked) == Set(Catalog.clothingSlots.flatMap { catalog.variants[$0] ?? [] }))
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

/// A store the member unlocked opens on the street with its rack, and an unlocked prop joins
/// the starters; the rest stay shut.
@Test func unlocksOpenTheirStoresAndProps() throws {
    let unlockedAt = Date(timeIntervalSince1970: 1_800_000_000)
    let catalog = try Catalog.placeholder(unlocks: [
        Unlock(
            kind: .store, id: "deuce", unlockedAt: unlockedAt, sports: ["tennis", "pickleball", "squash"], checkIns: 3),
        Unlock(kind: .prop, id: "racket", unlockedAt: unlockedAt, sports: ["tennis", "squash"], checkIns: 1),
    ])
    #expect(catalog.stores.filter(\.isOpen).map(\.id) == ["warmup", "deuce"])
    #expect(catalog.props == ["bottle", "dumbbell", "racket"])
    #expect(
        catalog.rack(of: "deuce").map(\.variant) == [
            "deuce-polo", "deuce-cable", "deuce-dress", "deuce-shorts", "deuce-skirt", "deuce-pants", "deuce-court",
            "deuce-socks", "deuce-visor", "deuce-terry", "deuce-ball", "deuce-sweater",
        ])
    #expect(catalog.rack(of: "lap").isEmpty)
    // Its polo recolors in the store's colors; its court shoes keep their art's.
    #expect(catalog.swatches(for: "top", wearing: "deuce-polo").count == 4)
    #expect(catalog.swatches(for: "shoes", wearing: "deuce-court").isEmpty)
    #expect(
        catalog.variants["top"] == [
            "warmup-tee", "warmup-tank", "warmup-hoodie", "warmup-long", "warmup-raglan", "warmup-stripe", "deuce-polo",
            "deuce-cable", "deuce-dress",
        ])
}

/// A piece still locked hangs on its store's rack only as a box, nearest to opening first, and
/// never in what a look can wear; one the member unlocked hangs as any other.
@Test func lockedPiecesHangAsBoxes() throws {
    let unlockedAt = Date(timeIntervalSince1970: 1_800_000_000)
    let catalog = try Catalog.placeholder(
        unlocks: [Unlock(kind: .piece, id: "warmup-headphones", unlockedAt: unlockedAt, sports: [], checkIns: 2)],
        locked: [
            LockedPiece(id: "warmup-beanie", checkInsToGo: 4),
            LockedPiece(id: "warmup-stripe", checkInsToGo: 2),
            LockedPiece(id: "warmup-long", checkInsToGo: 18),
            // An older list may still name what was just unlocked: what the member holds wins.
            LockedPiece(id: "warmup-headphones", checkInsToGo: 1),
            // A piece in a closed store stays out of sight with it.
            LockedPiece(id: "deuce-cable", checkInsToGo: 13),
        ])
    #expect(catalog.lockedRack(of: "warmup").map(\.variant) == ["warmup-stripe", "warmup-long", "warmup-beanie"])
    #expect(catalog.lockedRack(of: "warmup").map(\.toGo) == [2, 18, 4])
    #expect(catalog.lockedRack(of: "deuce").map(\.variant) == ["deuce-cable"])
    #expect(
        !catalog.rack(of: "warmup").contains { ["warmup-stripe", "warmup-long", "warmup-beanie"].contains($0.variant) })
    #expect(catalog.rack(of: "warmup").contains { $0.variant == "warmup-headphones" })
    #expect(catalog.variants["top"] == ["warmup-tee", "warmup-tank", "warmup-hoodie", "warmup-raglan"])
    #expect(catalog.swatches(for: "top", wearing: "warmup-stripe").isEmpty)
    var generator = SystemRandomNumberGenerator()
    for _ in 0..<40 {
        let look = CharacterDraft.randomLook(from: catalog, using: &generator)
        #expect(look.variants["top"] != "warmup-stripe" && look.variants["hat"] != "warmup-beanie")
    }
}
