import AvatarArt
import AvatarDomain
import Testing

/// A bichon's chin fluff hangs below its head (`chin`), over the forearms, which the head covers
/// too, and under the hands, so a hand at the chest or the face stays in front of it. Only the
/// bichon has one.
@Test func aBichonsChinIsOverTheForearmsAndUnderTheHands() throws {
    for body in try PlaceholderCharacter.variants(for: "body") {
        let figure = try PlaceholderCharacter.figure(wearing: Outfit(["body": body]))
        #expect(try figure.part("chin").art.isEmpty == (body != "bichon"), "\(body)")
        for side in ["L", "R"] {
            #expect(try figure.index("chin") > figure.index(PartID("arm\(side)Fore")))
            #expect(try figure.index("chin") < figure.index(PartID("arm\(side)")))
        }
    }
}
