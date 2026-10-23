import APIContract
import Contracts
import Foundation
import Testing

/// A catalog from a newer server: another section, another short list and a field on a sport
/// that this build has never heard of. The build still reads the sports it knows.
private let newer = #"""
    {"version": 1,
     "scenes": {"pool": {"icon": "drop"}},
     "sports": {
       "categories": [{"id": "racket", "names": {"zhHans": "球拍", "en": "Racket", "zhHant": "球拍"},
         "sports": [{"id": "padel", "names": {"zhHans": "板式网球", "en": "Padel", "zhHant": "板式網球"},
           "icon": "figure.tennis", "offered": true, "season": "summer"}]}],
       "picks": {"signUpCommon": ["padel"], "signUpMore": [], "checkInQuick": ["padel"], "winter": []}}}
    """#

@Test func aCatalogWithMoreThanThisBuildKnowsStillReads() throws {
    let wire = try JSONDecoder().decode(Components.Schemas.Catalog.self, from: Data(newer.utf8))
    let sports = SportCatalog(wire.sports)
    #expect(sports.entry(for: "padel")?.names.english == "Padel")
    #expect(sports.entry(for: "padel")?.category == "racket")
    #expect(sports.signUpCommon == ["padel"])
    #expect(sports.checkInQuick == ["padel"])
}
