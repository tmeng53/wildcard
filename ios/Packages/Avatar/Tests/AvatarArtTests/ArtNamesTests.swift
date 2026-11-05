import AvatarDomain
import Contracts
import Foundation
import Testing

@testable import AvatarArt

// Art added by upload carries its own names (`avatar/names.json`), so a new store and its
// pieces are named without an app release. Nothing is bundled.

private let trot = Data(
    #"""
    {"version": 1,
     "variants": {
       "trot-bib": {"zhHans": "烤火鸡号码布", "en": "Turkey Bib", "zhHant": "烤火雞號碼布"},
       "mouth/trot-pie": {"zhHans": "派嘴", "en": "Pie Mouth", "zhHant": "派嘴"}},
     "stores": {
       "trot": {
         "name": {"zhHans": "TURKEY TROT", "en": "TURKEY TROT", "zhHant": "TURKEY TROT"},
         "local": {"zhHans": "火鸡全开", "en": "Turkey Trot", "zhHant": "火雞全開"},
         "limited": {"zhHans": "感恩节限定", "en": "Thanksgiving only", "zhHant": "感恩節限定"}}}}
    """#.utf8)

@Test func uploadedNamesReadInEachLanguage() throws {
    let names = try ArtNames.decode(trot)
    #expect(names.variant("trot-bib", in: Slot("acc"))?.english == "Turkey Bib")
    #expect(names.variant("trot-pie", in: Slot("mouth"))?.simplifiedChinese == "派嘴")
    #expect(names.variant("trot-pie", in: Slot("top")) == nil)
    let store = try #require(names.stores["trot"])
    #expect(store.local.traditionalChinese == "火雞全開")
    #expect(store.limited?.simplifiedChinese == "感恩节限定")
    #expect(store.unlock == nil)
    #expect(ArtTree.reads(trot, at: "avatar/names.json"))
}

@Test func namesTheAppCantReadAreRefused() {
    let noLocal = Data(
        #"{"version":1,"stores":{"trot":{"name":{"zhHans":"T","en":"T","zhHant":"T"}}}}"#.utf8)
    let noEnglish = Data(#"{"version":1,"variants":{"trot-bib":{"zhHans":"号码布","zhHant":"號碼布"}}}"#.utf8)
    #expect(!ArtTree.reads(noLocal, at: "avatar/names.json"))
    #expect(!ArtTree.reads(noEnglish, at: "avatar/names.json"))
    #expect(!ArtTree.reads(Data(#"{"version":2}"#.utf8), at: "avatar/names.json"))
    #expect(!ArtTree.reads(trot, at: "avatar/art/acc/trot-bib/names.json"))
}

@Test func nothingUploadedNamesNothing() {
    #expect(PlaceholderCharacter.names() == .none)
}
