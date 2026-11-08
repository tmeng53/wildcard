import AvatarDomain
import Foundation
import Testing

@testable import AvatarArt

/// Every bundled store has a model for its window, dressed in that store's own clothes, and each
/// piece it wears is art this build draws.
@Test func everyStoreHasAWindowModelInItsOwnClothes() throws {
    let choices = try PlaceholderCharacter.editorChoices()
    for store in choices.stores {
        let window = try #require(PlaceholderCharacter.storeWindow(store.id), "\(store.id)")
        let clothes = window.outfit.variants.filter {
            ["top", "bottom", "shoes", "hat", "acc"].contains($0.key.rawValue)
        }
        #expect(!clothes.isEmpty)
        #expect(clothes.values.allSatisfy { $0.hasPrefix("\(store.id)-") }, "\(store.id)")
        #expect(try PlaceholderCharacter.drawable(window.outfit) == window.outfit, "\(store.id)")
        _ = try PlaceholderCharacter.figure(wearing: window.outfit)
    }
    #expect(PlaceholderCharacter.storeWindow("nowhere") == nil)
}

@Test func aStoreWindowReadsItsLookPersonaAndColours() throws {
    let window = try StoreWindow.decode(
        Data(
            ##"{"version": 1, "persona": "shy", "look": {"body": "peach", "hair": "curls"}, "colors": {"hair": "#2A2333", "body": "brown"}}"##
                .utf8))
    #expect(window.persona == .shy)
    #expect(window.outfit.variants == ["body": "peach", "hair": "curls"])
    #expect(window.outfit.colors == ["hair": RGBAColor(red: 0x2A, green: 0x23, blue: 0x33)])
    #expect(
        try StoreWindow.decode(Data(#"{"version": 1, "persona": "moonwalk", "look": {}}"#.utf8)).persona == .energetic)
    #expect(throws: AvatarError.malformedJSON(#": unknown key "outfit""#)) {
        try StoreWindow.decode(Data(#"{"version": 1, "persona": "shy", "outfit": {}, "look": {}}"#.utf8))
    }
}
