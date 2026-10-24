import AvatarArt
import AvatarDomain
import AvatarLooks
import Testing

/// Every look carries the 战报's gold medal and award crown, hidden until the story shows them:
/// the medal on the chest over the top and under the arms, the crown over any hat.
@Test func everyLookCarriesTheMedalAndTheCrownHidden() throws {
    for look in Looks.squad {
        let figure = try PlaceholderCharacter.figure(wearing: look)
        let rest = figure.layout(figure.restPose)
        for part in ["medal", "award"] as [PartID] {
            #expect(try figure.part(part).art.count == 1, "\(part)")
            #expect(try rest[figure.index(part)].opacity == 0, "\(part)")
        }
        let order = figure.parts.map(\.id)
        #expect(order.firstIndex(of: "medal") == (order.firstIndex(of: "torso") ?? 0) + 1)
        #expect(order.firstIndex(of: "award") == (order.firstIndex(of: "crown") ?? 0) + 1)
    }
}

/// The medal's ribbon takes the scene's colour; the gold stays gold.
@Test func theRibbonTakesTheScenesColour() throws {
    let accent = RGBAColor(red: 51, green: 102, blue: 204)
    let gold = RGBAColor(red: 0xE2, green: 0xBF, blue: 0x74)
    var look = PlaceholderCharacter.lifter
    look.colors["medal"] = accent
    let plain = try PlaceholderCharacter.figure(wearing: PlaceholderCharacter.lifter).part("medal").art
    let ribbon = try PlaceholderCharacter.figure(wearing: look).part("medal").art
    #expect(plain != ribbon)
    let shapes = ribbon.flatMap(\.shapes)
    #expect(shapes.contains { $0.stroke?.color == accent })
    #expect(shapes.contains { $0.fill == gold })
}
