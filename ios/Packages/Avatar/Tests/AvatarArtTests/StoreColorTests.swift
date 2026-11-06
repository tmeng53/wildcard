import AvatarArt
import Foundation
import Testing

/// Each store's colour is the first non-grey fill of its badge: WARM-UP's red dot, not its mist tile.
@Test func everyStoreTakesItsColourFromItsBadge() {
    let hex = { (store: String) -> String? in
        PlaceholderCharacter.storeColor(store).map { String(format: "#%02X%02X%02X", $0.red, $0.green, $0.blue) }
    }
    #expect(hex("warmup") == "#E65345")
    #expect(hex("lap") == "#2D5BA0")
    #expect(hex("nolook") == "#9062DE")
    #expect(hex("moss") == "#4F6B22")
    #expect(hex("halfmoon") == "#9ED9C8")
    #expect(hex("deuce") == "#24396B")
    #expect(hex("powder") == "#4C5BB0")
    #expect(hex("nowhere") == nil)
}
