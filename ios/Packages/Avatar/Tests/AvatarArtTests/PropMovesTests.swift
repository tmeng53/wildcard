import AvatarArt
import AvatarDomain
import AvatarLooks
import Testing

/// The props a hand can hold, each with a move of its own: the first batch.
let heldProps = [
    "badminton", "bottle", "chalkbag", "dumbbell", "goggles", "kettlebell", "pickleball", "pingpong", "racket",
    "yogamat",
]

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
        #expect(
            nearlyEqual(shown(figure.pose(bound, at: move.duration)), shown(figure.restPose)), "\(prop) ends at rest")
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
@Test(arguments: heldProps)
func everyPropIsHeldInAFist(prop: String) throws {
    let figure = try PlaceholderCharacter.figure(wearing: Outfit(["body": "peach", "prop": prop]))
    #expect(try #require(figure.part("gripR").art.first).shapes.isEmpty == false)
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
