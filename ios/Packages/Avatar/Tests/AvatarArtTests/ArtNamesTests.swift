import AvatarDomain
import Contracts
import Foundation
import Testing

@testable import AvatarArt

// Art carries its own names (`avatar/names.json`), so a store and its pieces are named and
// renamed without an app release: the bundled file names every store this build ships with, and
// an uploaded one stands in front of it word by word.

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
         "limited": {"zhHans": "感恩节限定", "en": "Thanksgiving only", "zhHant": "感恩節限定"},
         "limitedColor": "#c8553d"}}}
    """#.utf8)

@Test func uploadedNamesReadInEachLanguage() throws {
    let names = try ArtNames.decode(trot)
    #expect(names.variant("trot-bib", in: Slot("acc"))?.english == "Turkey Bib")
    #expect(names.variant("trot-pie", in: Slot("mouth"))?.simplifiedChinese == "派嘴")
    #expect(names.variant("trot-pie", in: Slot("top")) == nil)
    let store = try #require(names.stores["trot"])
    #expect(store.local.traditionalChinese == "火雞全開")
    #expect(store.limited?.simplifiedChinese == "感恩节限定")
    #expect(store.limitedColor == RGBAColor(red: 200, green: 85, blue: 61))
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

@Test func aLimitedTagsColourThatIsntOneIsLeftOut() throws {
    let file = Data(
        #"""
        {"version": 1, "stores": {"trot": {
          "name": {"zhHans": "T", "en": "T", "zhHant": "T"},
          "local": {"zhHans": "火鸡", "en": "Turkey", "zhHant": "火雞"},
          "limitedColor": "orange"}}}
        """#.utf8)
    #expect(try ArtNames.decode(file).stores["trot"]?.limitedColor == nil)
}

@Test func theBundledNamesNameEveryStoreThisBuildShips() throws {
    let names = PlaceholderCharacter.bundledNames
    #expect(names.stores.keys.sorted() == ["deuce", "halfmoon", "lap", "moss", "nolook", "powder", "warmup"])
    #expect(names.variants.isEmpty)
    let powder = try #require(names.stores["powder"])
    #expect(powder.name.english == "POWDER DAY")
    #expect(powder.limited?.simplifiedChinese == "冬季限定")
    #expect(powder.limitedColor == RGBAColor(red: 0x1E, green: 0x6A, blue: 0x9E))
    #expect(names.stores["lap"]?.unlock?.simplifiedChinese == "跑步、快走或徒步 3 次解锁")
    // Nothing downloaded in tests: the bundled names are all there is.
    #expect(PlaceholderCharacter.names() == names)
    let bundled = try Data(contentsOf: PlaceholderCharacter.folder.appending(path: "names.json"))
    #expect(ArtTree.reads(bundled, at: "avatar/names.json"))
}

@Test func anUploadedStoreStandsInFrontWordByWord() throws {
    let uploaded = try ArtNames.decode(
        Data(
            #"""
            {"version": 1, "stores": {"lap": {
              "name": {"zhHans": "LAP NINE", "en": "LAP NINE", "zhHant": "LAP NINE"},
              "local": {"zhHans": "第九圈", "en": "Lap nine", "zhHant": "第九圈"},
              "tagline": {"zhHans": "新的一句。", "en": "A new line.", "zhHant": "新的一句。"}}}}
            """#.utf8)
    ).overlaid(by: try ArtNames.decode(trot))
    let names = PlaceholderCharacter.bundledNames.overlaid(by: uploaded)
    let lap = try #require(names.stores["lap"])
    #expect(lap.tagline?.english == "A new line.")
    // Words the upload leaves out keep the bundled ones.
    #expect(lap.unlock?.simplifiedChinese == "跑步、快走或徒步 3 次解锁")
    #expect(lap.sports == PlaceholderCharacter.bundledNames.stores["lap"]?.sports)
    // A store only the upload names is added, and its variants come with it.
    #expect(names.stores["trot"]?.local.simplifiedChinese == "火鸡全开")
    #expect(names.variant("trot-bib", in: Slot("acc"))?.english == "Turkey Bib")
}
