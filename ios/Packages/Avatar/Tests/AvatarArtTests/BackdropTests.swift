import AvatarArt
import AvatarDomain
import Foundation
import Testing

/// The bundled list reads, in order, and 毛头 sits on its track colour.
@Test func bundledBackdropsAndTheCoachesPicks() {
    #expect(PlaceholderCharacter.backdrops.entries.map(\.id) == ["track", "pool", "gym", "tennis", "climbing", "ski"])
    #expect(CoachCharacter.backdrop("xiaohun") == RGBAColor(red: 0xF8, green: 0xDD, blue: 0xD9))
    #expect((try? CoachCharacter.figure("xiaohun"))?.backdrop == RGBAColor(red: 0xF8, green: 0xDD, blue: 0xD9))
    // A coach without a pick sits on the page's colour.
    #expect(CoachCharacter.backdrop("papa") == nil)
}

/// An id the list doesn't have picks nothing, and a colour that isn't `#rrggbb` refuses the list.
@Test func backdropsReadOnlyWhatDraws() throws {
    let list = try Backdrops.decode(Data(##"{"version":1,"backdrops":[{"id":"tennis","color":"#DDE6CC"}]}"##.utf8))
    #expect(list.color("tennis") == RGBAColor(red: 0xDD, green: 0xE6, blue: 0xCC))
    #expect(list.color("lava") == nil)
    #expect(throws: AvatarError.self) {
        try Backdrops.decode(Data(##"{"version":1,"backdrops":[{"id":"x","color":"mint"}]}"##.utf8))
    }
    #expect(try BackdropPick.decode(Data(##"{"version":1,"backdrop":"tennis"}"##.utf8)) == "tennis")
    #expect(throws: AvatarError.self) { try BackdropPick.decode(Data(##"{"version":2,"backdrop":"tennis"}"##.utf8)) }
}
