import APIContract
import Contracts
import Foundation
import Testing

/// A catalog from a newer server: another section, another short list and a field on a sport
/// and on a dice line that this build has never heard of. The build still reads what it knows.
private let newer = #"""
    {"version": 1,
     "venues": {"pool": {"icon": "drop"}},
     "sports": {
       "categories": [{"id": "racket", "names": {"zhHans": "球拍", "en": "Racket", "zhHant": "球拍"}, "color": "#4F6B22",
         "sports": [{"id": "padel", "names": {"zhHans": "板式网球", "en": "Padel", "zhHant": "板式網球"},
           "shortNames": {"zhHans": "板网", "en": "Padel", "zhHant": "板網"},
           "icon": "figure.tennis", "offered": true, "season": "summer"}]}],
       "picks": {"signUpCommon": ["padel"], "checkInQuick": ["padel"], "winter": []}},
     "disclaimerDice": {"lines": [{"zhHans": "腿说休息", "en": "Legs said rest", "zhHant": "腿說休息", "mood": "tired"}]}}
    """#

@Test func aCatalogWithMoreThanThisBuildKnowsStillReads() throws {
    let wire = try JSONDecoder().decode(Components.Schemas.Catalog.self, from: Data(newer.utf8))
    let catalog = AppCatalog(wire, otherwise: .empty)
    #expect(
        catalog.diceLines
            == [CatalogNames(simplifiedChinese: "腿说休息", english: "Legs said rest", traditionalChinese: "腿說休息")])
    let sports = catalog.sports
    #expect(sports.entry(for: "padel")?.names.english == "Padel")
    #expect(sports.entry(for: "padel")?.category == "racket")
    #expect(sports.color(of: "padel") == "#4F6B22")
    #expect(sports.entry(for: "padel")?.shortNames?.simplifiedChinese == "板网")
    #expect(sports.signUpCommon == ["padel"])
    #expect(sports.checkInQuick == ["padel"])
}

/// A catalog from a server from before a section was added: what it lacks is the build's own.
@Test func aSectionTheServerDidntSendIsTheBuildsOwn() throws {
    let older = #"{"version": 1, "disclaimerDice": {"lines": []}}"#
    let wire = try JSONDecoder().decode(Components.Schemas.Catalog.self, from: Data(older.utf8))
    let own = AppCatalog(
        sports: SportCatalog(categories: [], signUpCommon: [], checkInQuick: []),
        diceLines: [CatalogNames(simplifiedChinese: "累了", english: "Tired", traditionalChinese: "累了")])
    #expect(AppCatalog(wire, otherwise: own) == own)
}

/// The bundled catalog's starter street: WARM-UP and its starters, never a store on a switch.
@Test func theBundledCatalogsStarterShelfLeavesOutTheWinterStore() throws {
    let text = try String(
        contentsOf: URL(filePath: #filePath).deletingLastPathComponent()
            .appending(path: "../../../Backend/Sources/Backend/Resources/catalog.json"), encoding: .utf8)
    let wire = try JSONDecoder().decode(Components.Schemas.Catalog.self, from: Data(text.utf8))
    let stock = AppCatalog(wire, otherwise: .empty).starterStock
    #expect(stock.stores == [StreetStock.Store(id: "warmup", isOpen: true)])
    #expect(!stock.pieces.isEmpty)
    #expect(stock.pieces.allSatisfy { $0.store == "warmup" && $0.state == .available })
}

/// A scene added through the admin tools (TURKEY TROT's `trot`) is read with its names and
/// colours; one whose id can't be one is left out.
@Test func scenesAddedSinceAreRead() throws {
    let text = #"""
        {"version": 1, "scenes": {"scenes": [
          {"id": "trot", "names": {"zhHans": "火鸡大道", "en": "Turkey Trot", "zhHant": "火雞大道"},
           "colors": {"signature": "#B5532A", "onSignature": "#FFFFFF", "wash": "#FBEDE5", "text": "#8A3B1A",
             "floor": "#F3DCCD"}, "limited": true, "switchId": "thanksgiving"},
          {"id": "Bad-Id", "names": {"zhHans": "x", "en": "x", "zhHant": "x"},
           "colors": {"signature": "#000000", "onSignature": "#FFFFFF", "wash": "#FFFFFF", "text": "#000000",
             "floor": "#FFFFFF"}, "limited": false}]}}
        """#
    let wire = try JSONDecoder().decode(Components.Schemas.Catalog.self, from: Data(text.utf8))
    let scenes = AppCatalog(wire, otherwise: .empty).scenes
    #expect(scenes.map(\.id.rawValue) == ["trot"])
    #expect(scenes.first?.names.english == "Turkey Trot")
    #expect(scenes.first?.colors.floor == "#F3DCCD")
}
