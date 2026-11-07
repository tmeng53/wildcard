import AvatarArt
import AvatarDomain
import CharacterEditorDomain
import CharacterEditorUI
import Contracts
import Foundation
import Testing

/// POWDER DAY's pieces that open one winter check-in at a time, as the API lists them before any.
private let powderLocked = Dictionary(
    uniqueKeysWithValues: [
        "tuna", "ikura", "temaki", "nori", "tamago", "scarf", "edamame", "uni", "pants", "ebi", "ebifry", "maki",
        "salmonhelmet",
    ].enumerated().map { ("powder-\($1)", $0 + 1) })

private let unlockedAt = Date(timeIntervalSince1970: 1_800_000_000)

/// The 商店街 as the server sends it: every store, `closed` ones shut; the pieces of each store
/// in `earned` that is open, boxed when in `locked` and owned when in `owned`, otherwise available;
/// and what is owned in a closed store.
private func stock(
    earned: Set<String>, closed: Set<String> = [], locked: [String: Int] = [:], owned: Set<String> = []
) throws -> StreetStock {
    let stores = ["warmup", "lap", "nolook", "moss", "halfmoon", "deuce", "powder"]
    let wear = try PlaceholderCharacter.editorChoices().wear.values.joined()
    return StreetStock(
        stores: stores.map { StreetStock.Store(id: $0, isOpen: !closed.contains($0)) },
        pieces: wear.compactMap { piece in
            if owned.contains(piece.id) { return StreetStock.Piece(id: piece.id, store: piece.store, state: .owned) }
            guard earned.contains(piece.store), !closed.contains(piece.store) else { return nil }
            let state: StreetStock.State = locked[piece.id].map { .locked(toGo: $0) } ?? .available
            return StreetStock.Piece(id: piece.id, store: piece.store, state: state)
        })
}

/// A winter street for a member who just started: WARM-UP's nineteen pieces and POWDER DAY's
/// starters out, the rest of POWDER DAY boxed.
private func winterStart() throws -> StreetStock { try stock(earned: ["warmup", "powder"], locked: powderLocked) }

/// The bundled art gives the editor what the design shows: five species, WARM-UP's nineteen pieces
/// and POWDER DAY's four starters, the two props every member starts with, and swatches with a 原色
/// for exactly the pieces that recolor (POWDER DAY's keep their colours).
@Test func thePlaceholderCatalogComesFromTheArt() throws {
    let catalog = try Catalog.placeholder(stock: try winterStart())
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

/// The shopping street: seven stores in winter, WARM-UP and POWDER DAY open at the start and
/// first on the street, and
/// every piece of clothing on a rack, WARM-UP's nineteen pieces, tops first, then bottoms, shoes,
/// hats and accessories.
@Test func everyPieceHangsInAStore() throws {
    let catalog = try Catalog.placeholder(stock: try winterStart())
    #expect(catalog.stores.map(\.id) == ["warmup", "powder", "lap", "nolook", "moss", "halfmoon", "deuce"])
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
    let catalog = try Catalog.placeholder(
        stock: try stock(earned: ["warmup", "lap", "nolook", "moss", "halfmoon", "deuce", "powder"]))
    var generator = SystemRandomNumberGenerator()
    for _ in 0..<40 {
        let look = CharacterDraft.randomLook(from: catalog, using: &generator)
        var draft = CharacterDraft(catalog: catalog, look: look, persona: .deadpan, nickname: "")
        _ = try PlaceholderCharacter.figure(wearing: draft.outfit)
        draft.pick("bear", for: "body")
        _ = try PlaceholderCharacter.figure(wearing: draft.outfit)
    }
}

/// 随机 never puts on a piece that came in but isn't claimed yet: it waits on 商店街.
@Test func aRandomLookLeavesOutWhatIsntClaimed() throws {
    let catalog = try Catalog.placeholder(
        stock: try stock(earned: ["warmup", "lap", "nolook", "moss", "halfmoon", "deuce", "powder"]))
    let tops = catalog.variants["top"] ?? []
    #expect(tops.count > 1)
    let unclaimed = Set(tops.dropFirst())
    var generator = SystemRandomNumberGenerator()
    for _ in 0..<40 {
        let look = CharacterDraft.randomLook(from: catalog, using: &generator, leavingOut: unclaimed)
        #expect(look.variants.values.allSatisfy { !unclaimed.contains($0) })
    }
}

/// A limited store's starter the server sends as the member's while it is out has come in, so it
/// waits to be claimed, and a random look never puts it on until then.
@Test func aLimitedStarterOutComesInAndWaitsToBeClaimed() throws {
    let starters = try PlaceholderCharacter.editorChoices().wear.values.joined().filter { $0.store == "powder" }
    let starter = try #require(starters.first).id
    let stock = try stock(earned: ["warmup"], owned: [starter])
    let arrived = Catalog.arrived(unlocks: [], stock: stock)
    #expect(arrived == [starter])
    let catalog = try Catalog.placeholder(stock: stock)
    var generator = SystemRandomNumberGenerator()
    for _ in 0..<40 {
        let look = CharacterDraft.randomLook(from: catalog, using: &generator, leavingOut: arrived)
        #expect(!look.variants.values.contains(starter))
    }
}

/// A store the member unlocked opens on the street with its rack, and an unlocked prop joins
/// the starters; the rest stay shut.
@Test func unlocksOpenTheirStoresAndProps() throws {
    let catalog = try Catalog.placeholder(
        unlocks: [
            Unlock(
                kind: .store, id: "deuce", unlockedAt: unlockedAt, sports: ["tennis", "pickleball", "squash"],
                checkIns: 3),
            Unlock(kind: .prop, id: "racket", unlockedAt: unlockedAt, sports: ["tennis", "squash"], checkIns: 1),
        ], stock: try stock(earned: ["warmup", "deuce", "powder"], locked: powderLocked))
    #expect(catalog.stores.filter(\.isOpen).map(\.id) == ["warmup", "deuce", "powder"])
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
            "deuce-cable", "deuce-dress", "powder-salmon",
        ])
}

/// A piece still locked hangs on its store's rack only as a box, nearest to opening first across
/// slots, and never in what a look can wear; one the member unlocked hangs as any other. A store
/// not earned yet shows no rack.
@Test func lockedPiecesHangAsBoxes() throws {
    let catalog = try Catalog.placeholder(
        stock: try stock(
            earned: ["warmup", "powder"],
            locked: ["warmup-beanie": 4, "warmup-stripe": 2, "warmup-long": 18].merging(powderLocked) { $1 },
            owned: ["warmup-headphones"]))
    // Fewest 练了 to go first, whatever the slot: the beanie (a hat) before the long sleeve (a top).
    #expect(catalog.lockedRack(of: "warmup").map(\.variant) == ["warmup-stripe", "warmup-beanie", "warmup-long"])
    #expect(catalog.lockedRack(of: "warmup").map(\.toGo) == [2, 4, 18])
    #expect(catalog.lockedRack(of: "deuce").isEmpty && catalog.rack(of: "deuce").isEmpty)
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

/// While POWDER DAY is closed, what a member unlocked stays theirs: the store shows only those
/// pieces, without the starters or the 「？」 boxes, and leaves the street for a member who
/// unlocked none.
@Test func aClosedStoreKeepsWhatAMemberUnlocked() throws {
    let winter = try Catalog.placeholder(
        stock: try stock(earned: ["warmup", "powder"], locked: powderLocked, owned: ["powder-tuna"]))
    let summer = try Catalog.placeholder(
        stock: try stock(earned: ["warmup", "powder"], closed: ["powder"], owned: ["powder-tuna"]))
    #expect(winter.stores.map(\.id).prefix(2) == ["warmup", "powder"])
    #expect(summer.stores.first { $0.id == "powder" }?.isOpen == true)
    #expect(winter.lockedRack(of: "powder").count == 12)
    #expect(summer.lockedRack(of: "powder").isEmpty)
    #expect(
        winter.rack(of: "powder").map(\.variant) == [
            "powder-salmon", "powder-tuna", "powder-rice", "powder-saba", "powder-helmet",
        ])
    #expect(summer.rack(of: "powder").map(\.variant) == ["powder-tuna"])
    let newcomer = try Catalog.placeholder(stock: try stock(earned: ["warmup", "powder"], closed: ["powder"]))
    #expect(!newcomer.stores.map(\.id).contains("powder"))
    #expect(newcomer.rack(of: "powder").isEmpty)
}

/// Before the member's own street is read, the editor offers the starter street the app was
/// last given, and a store the art has no badge for is left out.
@Test func theStarterStreetStandsInUntilTheMembersOwn() throws {
    let starter = StreetStock(
        stores: [StreetStock.Store(id: "warmup", isOpen: true), StreetStock.Store(id: "newstore", isOpen: true)],
        pieces: [StreetStock.Piece(id: "warmup-tee", store: "warmup", state: .available)])
    StarterStock.shared.show(starter)
    defer { StarterStock.shared.show(.empty) }
    let catalog = try Catalog.placeholder()
    #expect(catalog.stores == [EditorChoices.Store(id: "warmup", isOpen: true)])
    #expect(catalog.variants["top"] == ["warmup-tee"])
}
