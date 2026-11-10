import AvatarArt
import AvatarDomain
import AvatarLooks
import Testing

/// The props a character can hold or stand on, each with a move of its own.
let heldProps = [
    "badminton", "basketball", "bottle", "broom", "chalkbag", "dumbbell", "gloves", "goggles", "helmet", "kettlebell",
    "pickleball", "pingpong", "racket", "skis", "snowboard", "soccerball", "yogamat",
]

/// A character standing with a prop plays its move over and over, at its persona's tempo (a
/// yoga mat's tree pose on the player card); one holding nothing stands in its persona's idle.
@Test func aHeldPropLoopsItsMove() throws {
    let mat = try #require(try PlaceholderCharacter.heldMove(wearing: Outfit(["prop": "yogamat"]), persona: .deadpan))
    let once = try #require(try PlaceholderCharacter.propMove(for: Outfit(["prop": "yogamat"])))
    #expect(mat.loops)
    #expect(mat.name == "yogamat")
    #expect(abs(mat.duration - once.duration / Persona.deadpan.accentTempo) < 0.001)
    #expect(try PlaceholderCharacter.heldMove(wearing: Outfit([:]), persona: .deadpan) == nil)
}

/// Every held prop has a move of its own that plays once, ends at rest and stays on the canvas
/// on every look holding it; a look holding nothing has none.
@Test(arguments: heldProps)
func everyPropHasItsMove(prop: String) throws {
    #expect(PlaceholderCharacter.variants(for: "prop") == heldProps)
    for var look in Looks.squad {
        look.variants["prop"] = prop
        let figure = try PlaceholderCharacter.figure(wearing: look)
        let move = try #require(try PlaceholderCharacter.propMove(for: look), "\(prop)")
        let bound = try figure.bind(move)
        #expect(!move.loops)
        #expect(move.name == prop)
        // Its own move turns the prop itself, so a prop that keeps level is left to it.
        #expect(move.holds == prop)
        // Its arms may end in front: the crossfade keeps them there until back at rest.
        var end = shown(figure.pose(bound, at: move.duration))
        for index in end.parts.indices { end.parts[index].front = 0 }
        #expect(nearlyEqual(end, shown(figure.restPose)), "\(prop) ends at rest")
        expectOnCanvas(figure, bound, for: move.duration, "\(prop) \(move.name)")
    }
}

/// The pose with hidden parts, such as a mat put away, left at rest: where they end up unseen
/// doesn't show.
func shown(_ pose: Pose) -> Pose {
    Pose(parts: pose.parts.map { $0.opacity == 0 ? PartPose(opacity: 0) : $0 })
}

@Test func emptyHandsHaveNoPropMove() throws {
    var emptyHanded = PlaceholderCharacter.lifter
    emptyHanded.variants["prop"] = nil
    #expect(try PlaceholderCharacter.propMove(for: emptyHanded) == nil)
}

/// The dumbbell is pressed overhead, the racket swung up behind the head for a serve.
@Test func propsMoveTheirOwnWay() throws {
    let figure = try PlaceholderCharacter.figure(wearing: PlaceholderCharacter.lifter)
    func armR(_ prop: String) throws -> [Double] {
        var look = PlaceholderCharacter.lifter
        look.variants["prop"] = prop
        let bound = try figure.bind(try #require(try PlaceholderCharacter.propMove(for: look)))
        let arm = try figure.index("armR")
        return (0...Int(bound.clip.duration * 100)).map { figure.pose(bound, at: Double($0) / 100).parts[arm].rotation }
    }
    let lift = try armR("dumbbell")
    #expect(lift.min() == -78)
    #expect(lift.max() == 0)
    let serve = try armR("racket")
    #expect(serve.min() == -112)
    #expect(serve.max() == 66)
}

/// A prop is held in a mitten fist the colors of the wearer's own hand: peach skin, a
/// recolored skin and a cat's ginger paw, outline included.
@Test(arguments: [
    (Outfit(["body": "peach", "prop": "racket"]), "#F5CDAE", "#B89A8B"),
    (
        Outfit(["body": "peach", "prop": "racket"], colors: ["body": RGBAColor(red: 0x8D, green: 0x5B, blue: 0x3C)]),
        "#8D5B3C", nil
    ),
    (Outfit(["body": "cat", "prop": "racket"]), "#F2A65A", "#B67E4E"),
])
func theGripIsTheWearersHand(look: Outfit, fill: String, stroke: String?) throws {
    let figure = try PlaceholderCharacter.figure(wearing: look)
    let hand = try #require(figure.part("armR").art.first?.shapes.last)
    let grip = try #require(figure.part("gripR").art.first)
    #expect(hand.fill?.hex == fill)
    if let stroke { #expect(hand.stroke?.color.hex == stroke) }
    #expect(grip.shapes.first?.fill == hand.fill)
    #expect(grip.shapes.allSatisfy { $0.stroke?.color == hand.stroke?.color })
}

/// Every held prop is drawn in a fist: a missing grip would leave the prop floating by the hand.
/// Boxing gloves are the fists themselves, and a snowboard is stood on, not held.
@Test(arguments: heldProps)
func everyPropIsHeldInAFist(prop: String) throws {
    let figure = try PlaceholderCharacter.figure(wearing: Outfit(["body": "peach", "prop": prop]))
    let gripped = try figure.part("gripR").art.flatMap(\.shapes).isEmpty == false
    #expect(gripped == !["gloves", "snowboard"].contains(prop))
}

/// Skis and a snowboard stay under the feet when nothing moves, and only they draw there (the
/// skis' tips over the boots too); the
/// skis' poles are held in both fists, the gloves worn on both hands.
@Test func gearUnderTheFeetAndInTheLeftHand() throws {
    for prop in heldProps {
        let figure = try PlaceholderCharacter.figure(wearing: Outfit(["body": "peach", "prop": prop]))
        let feet = try figure.part("propFeet")
        #expect(feet.restOpacity == 1)
        #expect(feet.art.flatMap(\.shapes).isEmpty == !["skis", "snowboard"].contains(prop), "\(prop)")
        // The skis point at the viewer, so their tips come out in front of the boots.
        let toes = try figure.part("propToes")
        #expect(toes.restOpacity == 1)
        #expect(toes.art.flatMap(\.shapes).isEmpty == (prop != "skis"), "\(prop)")
        let left = try figure.part("propL").art.flatMap(\.shapes)
        #expect(left.isEmpty == !["skis", "gloves"].contains(prop), "\(prop)")
        let fist = try figure.part("gripL").art.flatMap(\.shapes)
        #expect(fist.isEmpty == (prop != "skis"), "\(prop)")
    }
}

/// Tapping my character on the home plays the move of the prop it holds, once, at my persona's
/// tempo; holding nothing, it cheers.
@Test func aTapPlaysThePropsMoveOrACheer() throws {
    let lifting = try PlaceholderCharacter.signatureMove(wearing: Outfit(["prop": "dumbbell"]), persona: .drama)
    #expect(lifting.name == "dumbbell")
    #expect(!lifting.loops)
    let press = try #require(try PlaceholderCharacter.propMove(for: Outfit(["prop": "dumbbell"])))
    #expect(lifting.duration == press.duration / Persona.drama.accentTempo)
    let emptyHanded = try PlaceholderCharacter.signatureMove(wearing: Outfit([:]), persona: .shy)
    #expect(emptyHanded.name == "cheer")
}
