import AvatarArt
import AvatarDomain
import AvatarLooks
import Foundation
import Testing

/// A bichon's whole chin fluff (`chin`) sits behind the arms, so a raised arm stays in front of it;
/// its middle (`chinFront`) covers the shoulders of hanging ones. Only the bichon has either.
@Test func aBichonsChinSitsOverTheShouldersOnly() throws {
    for body in try PlaceholderCharacter.variants(for: "body") {
        let figure = try PlaceholderCharacter.figure(wearing: Outfit(["body": body]))
        let isBichon = body == "bichon"
        #expect(try figure.part("chin").art.isEmpty == !isBichon && figure.part("chinFront").art.isEmpty == !isBichon)
        #expect(try figure.index("chin") < figure.index("armL") && figure.index("chin") < figure.index("armR"))
        #expect(
            try figure.index("chinFront") > figure.index("armL") && figure.index("chinFront") > figure.index("armR"))
        #expect(
            try figure.index("chinFront") < figure.index("flexL") && figure.index("chinFront") < figure.index("flexR"))
    }
}
