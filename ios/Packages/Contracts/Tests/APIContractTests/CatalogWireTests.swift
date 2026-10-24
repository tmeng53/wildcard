import APIContract
import Contracts
import Foundation
import Testing

/// A catalog from a newer server: another section, another short list and a field on a sport
/// and on a dice line that this build has never heard of. The build still reads what it knows.
private let newer = #"""
    {"version": 1,
     "scenes": {"pool": {"icon": "drop"}},
     "sports": {
       "categories": [{"id": "racket", "names": {"zhHans": "球拍", "en": "Racket", "zhHant": "球拍"},
         "sports": [{"id": "padel", "names": {"zhHans": "板式网球", "en": "Padel", "zhHant": "板式網球"},
           "shortNames": {"zhHans": "板网", "en": "Padel", "zhHant": "板網"},
           "icon": "figure.tennis", "offered": true, "season": "summer"}]}],
       "picks": {"signUpCommon": ["padel"], "checkInQuick": ["padel"], "winter": []}},
     "disclaimerDice": {"lines": [{"zhHans": "腿说休息", "en": "Legs said rest", "zhHant": "腿說休息", "mood": "tired"}]}}
    """#

@Test func aCatalogWithMoreThanThisBuildKnowsStillReads() throws {
    let wire = try JSONDecoder().decode(Components.Schemas.Catalog.self, from: Data(newer.utf8))
    let catalog = AppCatalog(wire)
    #expect(
        catalog.diceLines
            == [CatalogNames(simplifiedChinese: "腿说休息", english: "Legs said rest", traditionalChinese: "腿說休息")])
    let sports = catalog.sports
    #expect(sports.entry(for: "padel")?.names.english == "Padel")
    #expect(sports.entry(for: "padel")?.category == "racket")
    #expect(sports.entry(for: "padel")?.shortNames?.simplifiedChinese == "板网")
    #expect(sports.signUpCommon == ["padel"])
    #expect(sports.checkInQuick == ["padel"])
}
