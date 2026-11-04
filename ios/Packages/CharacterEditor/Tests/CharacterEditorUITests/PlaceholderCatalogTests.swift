import AvatarArt
import AvatarDomain
import CharacterEditorDomain
import CharacterEditorUI
import Contracts
import Foundation
import Testing

/// POWDER DAY's pieces that open one winter check-in at a time, as the API lists them before any.
private let powderLocked = [
    "tuna", "ikura", "temaki", "nori", "tamago", "scarf", "edamame", "uni", "pants", "ebi", "ebifry", "maki",
    "salmonhelmet",
].enumerated().map { LockedPiece(id: "powder-\($1)", checkInsToGo: $0 + 1) }

/// The bundled art gives the editor what the design shows: five species, WARM-UP's nineteen pieces
/// and POWDER DAY's four starters, the two props every member starts with, and swatches with a 原色
/// for exactly the pieces that recolor (POWDER DAY's keep their colours).
@Test func thePlaceholderCatalogComesFromTheArt() throws {
    let catalog = try Catalog.placeholder(locked: powderLocked)
    #expect(catalog.species.map(\.id) == ["person", "cat", "dog", "rabbit", "bear"])
    #expect(catalog.props == ["bottle", "dumbbell"])
    #expect(
        catalog.variants["top"] == [
            "warmup-tee", "warmup-tank", "warmup-hoodie", "warmup-long", "warmup-raglan", "warmup-stripe",
            "powder-salmon",
        ])
    #expect(
        catalog.variants["bottom"] == [
            "warmup-shorts", "warmup-joggers", "warmup-leggings", "warmup-overalls", "powder-rice",
        ])
    #expect(catalog.variants["shoes"] == ["warmup-canvas", "warmup-runner", "warmup-hightop", "powder-saba"])
    #expect(
        catalog.variants["hat"] == [
            "warmup-cap", "warmup-headband", "warmup-beanie", "warmup-headphones", "powder-helmet",
        ])
    #expect(catalog.variants["acc"] == ["warmup-towel", "warmup-waistbag"])
    #expect(catalog.swatches(for: "body", wearing: "peach").count == 7)
    #expect(catalog.swatches(for: "body", wearing: "calico").isEmpty)
    #expect(catalog.originals["top"]?["warmup-tee"] == RGBAColor(hex: "#F4F6FA"))
    for slot in Catalog.clothingSlots {
        for variant in catalog.variants[slot] ?? [] {
            let fixed = variant.hasPrefix("powder-")
            #expect(catalog.swatches(for: slot, wearing: variant).count == (fixed ? 0 : 5), "\(variant)")
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

/// The shopping street: seven stores in winter, WARM-UP and POWDER DAY open at the start, and
/// every piece of clothing on a rack, WARM-UP's nineteen pieces, tops first, then bottoms, shoes,
/// hats and accessories.
@Test func everyPieceHangsInAStore() throws {
    let catalog = try Catalog.placeholder(locked: powderLocked, inSeason: { _ in true })
    #expect(catalog.stores.map(\.id) == ["warmup", "lap", "nolook", "moss", "halfmoon", "deuce", "powder"])
    #expect(catalog.stores.filter(\.isOpen).map(\.id) == ["warmup", "powder"])
    #expect(
        catalog.rack(of: "powder").map(\.variant) == ["powder-salmon", "powder-rice", "powder-saba", "powder-helmet"])
    #expect(catalog.lockedRack(of: "powder").first?.variant == "powder-tuna")
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

/// Every random look the editor can start from is one the art can draw, POWDER DAY's every piece
/// included.
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
    let catalog = try Catalog.placeholder(
        unlocks: [
            Unlock(
                kind: .store, id: "deuce", unlockedAt: unlockedAt, sports: ["tennis", "pickleball", "squash"],
                checkIns: 3),
            Unlock(kind: .prop, id: "racket", unlockedAt: unlockedAt, sports: ["tennis", "squash"], checkIns: 1),
        ], locked: powderLocked)
    #expect(catalog.stores.filter(\.isOpen).map(\.id) == ["warmup", "deuce", "powder"])
    #expect(catalog.props == ["bottle", "dumbbell", "racket"])
    #expect(
        catalog.rack(of: "deuce").map(\.variant) == [
            "deuce-polo", "deuce-cable", "deuce-dress", "deuce-shorts", "deuce-skirt", "deuce-pants", "deuce-court",
            "deuce-socks", "deuce-visor", "deuce-terry", "deuce-sweater",
        ])
    #expect(catalog.rack(of: "lap").isEmpty)
    // Its polo recolors in the store's colors; its court shoes keep their art's.
    #expect(catalog.swatches(for: "top", wearing: "deuce-polo").count == 4)
    #expect(catalog.swatches(for: "shoes", wearing: "deuce-court").isEmpty)
    #expect(
        catalog.variants["top"] == [
            "warmup-tee", "warmup-tank", "warmup-hoodie", "warmup-long", "warmup-raglan", "warmup-stripe", "deuce-polo",
            "deuce-cable", "deuce-dress", "powder-salmon",
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
        ] + powderLocked)
    #expect(catalog.lockedRack(of: "warmup").map(\.variant) == ["warmup-stripe", "warmup-long", "warmup-beanie"])
    #expect(catalog.lockedRack(of: "warmup").map(\.toGo) == [2, 18, 4])
    #expect(catalog.lockedRack(of: "deuce").map(\.variant) == ["deuce-cable"])
    #expect(
        !catalog.rack(of: "warmup").contains { ["warmup-stripe", "warmup-long", "warmup-beanie"].contains($0.variant) })
    #expect(catalog.rack(of: "warmup").contains { $0.variant == "warmup-headphones" })
    #expect(
        catalog.variants["top"] == ["warmup-tee", "warmup-tank", "warmup-hoodie", "warmup-raglan", "powder-salmon"])
    #expect(catalog.swatches(for: "top", wearing: "warmup-stripe").isEmpty)
    var generator = SystemRandomNumberGenerator()
    for _ in 0..<40 {
        let look = CharacterDraft.randomLook(from: catalog, using: &generator)
        #expect(look.variants["top"] != "warmup-stripe" && look.variants["hat"] != "warmup-beanie")
    }
}

/// POWDER DAY unlocks only in the ski scene's season, and stays the member's all year: out of it
/// the store is still on the street with what they hold, only without the 「？」 boxes.
@Test func aSeasonalStoreKeepsWhatAMemberHoldsOutOfSeason() throws {
    let unlockedAt = Date(timeIntervalSince1970: 1_800_000_000)
    let tuna = Unlock(kind: .piece, id: "powder-tuna", unlockedAt: unlockedAt, sports: ["ski"], checkIns: 1)
    let winter = try Catalog.placeholder(unlocks: [tuna], locked: powderLocked, inSeason: { $0 == "ski" })
    let summer = try Catalog.placeholder(unlocks: [tuna], locked: powderLocked, inSeason: { _ in false })
    #expect(winter.stores.map(\.id).last == "powder" && summer.stores.map(\.id).last == "powder")
    #expect(winter.lockedRack(of: "powder").count == 12)
    #expect(summer.lockedRack(of: "powder").isEmpty)
    #expect(
        summer.rack(of: "powder").map(\.variant) == [
            "powder-salmon", "powder-tuna", "powder-rice", "powder-saba", "powder-helmet",
        ])
    #expect(summer.rack(of: "powder").map(\.variant) == winter.rack(of: "powder").map(\.variant))
}

/// The seasons come from the catalog, in New York days, and run over New Year; a scene the
/// catalog gives no season is open all year.
@Test func storeSeasonsFollowTheCatalog() throws {
    let seasons = StoreSeasons()
    #expect(seasons.isOpen("ski", on: try LocalDay("2026-07-01")))
    seasons.show(["ski": SceneSeason(start: try #require(MonthDay("11-15")), end: try #require(MonthDay("03-31")))])
    #expect(seasons.isOpen("ski", on: try LocalDay("2026-11-15")))
    #expect(seasons.isOpen("ski", on: try LocalDay("2027-03-31")))
    #expect(!seasons.isOpen("ski", on: try LocalDay("2027-04-01")))
    #expect(!seasons.isOpen("ski", on: try LocalDay("2026-11-14")))
    #expect(seasons.isOpen("gym", on: try LocalDay("2026-07-01")))
}
