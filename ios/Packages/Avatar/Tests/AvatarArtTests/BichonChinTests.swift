import AvatarArt
import AvatarDomain
import Testing

/// A bichon's chin fluff hangs below its head (`chin`) and, like the head, over both of each arm's
/// copies, so no arm ever covers it. Only the bichon has one.
@Test func aBichonsChinIsOverTheArms() throws {
    for body in try PlaceholderCharacter.variants(for: "body") {
        let figure = try PlaceholderCharacter.figure(wearing: Outfit(["body": body]))
        #expect(try figure.part("chin").art.isEmpty == (body != "bichon"), "\(body)")
        for side in ["L", "R"] {
            #expect(try figure.index("chin") > figure.index(PartID("arm\(side)")))
        }
    }
}
