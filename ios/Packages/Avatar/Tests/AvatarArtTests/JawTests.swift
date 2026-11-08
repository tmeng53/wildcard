import AvatarArt
import AvatarDomain
import Testing

/// The arms are drawn after the head so a raised hand stays in front of the face, which puts each
/// shoulder over the chin, and the accessory after the arms so its straps lie over the sleeves. Every
/// head but the bichon's (whose fluff does it, `chinFrontL`/`R`) draws the halves of its chin again
/// (`jawL`, `jawR`) after both arms and the accessory and before what the hand holds, so no sleeve
/// or strap crosses the chin's outline.
@Test func everyChinCoversItsShoulders() throws {
    for body in try PlaceholderCharacter.variants(for: "body") {
        let figure = try PlaceholderCharacter.figure(wearing: Outfit(["body": body]))
        for (jaw, arm, prop): (PartID, PartID, PartID) in [("jawL", "armL", "propL"), ("jawR", "armR", "propR")] {
            #expect(try figure.part(jaw).art.isEmpty == (body == "bichon"), "\(body) \(jaw)")
            #expect(try figure.index(jaw) > figure.index("armL"))
            #expect(try figure.index(jaw) > figure.index("armR"))
            #expect(try figure.index(jaw) > figure.index("acc"))
            #expect(try figure.index(jaw) < figure.index(prop))
            #expect(try figure.part(jaw).hides?.arm == figure.index(arm))
        }
    }
}

/// Hair that reaches the chin is cut with it, so a bob's ends stay over the jaw, not under it.
@Test func hairDownToTheChinCoversTheShouldersToo() throws {
    for hair in ["bob", "long", "pigtails", "wolf"] {
        let figure = try PlaceholderCharacter.figure(wearing: Outfit(["body": "peach", "hair": hair]))
        #expect(try figure.part("jawL").art.count == 2, "\(hair)")
    }
    let short = try PlaceholderCharacter.figure(wearing: Outfit(["body": "peach", "hair": "buzz"]))
    #expect(try short.part("jawL").art.count == 1)
}

/// A jaw stays while its arm hangs, swings or crosses the chest, and goes at once when the arm comes
/// up past 95 degrees, where a hand reaches the face: a switch, since a half-faded chin shows the
/// sleeve through it.
@Test func aJawGivesWayToAHandAtTheFace() throws {
    let figure = try PlaceholderCharacter.figure(wearing: Outfit(["body": "peach"]))
    func shown(_ jaw: PartID, armL: Double, armR: Double) throws -> Double {
        var pose = figure.restPose
        pose.parts[try figure.index("armL")].rotation = armL
        pose.parts[try figure.index("armR")].rotation = armR
        return figure.layout(pose)[try figure.index(jaw)].opacity
    }
    #expect(try shown("jawL", armL: 0, armR: 0) == 1)
    #expect(try shown("jawL", armL: 60, armR: 0) == 1)
    #expect(try shown("jawL", armL: -90, armR: 0) == 1)
    #expect(try shown("jawL", armL: 100, armR: 0) == 0)
    #expect(try shown("jawL", armL: -120, armR: 0) == 0)
    #expect(try shown("jawR", armL: 120, armR: 0) == 1)
    #expect(try shown("jawR", armL: 0, armR: -100) == 0)
}
