import AvatarArt
import AvatarDomain
import AvatarLooks
import Testing

/// Every prop the editor offers has a move of its own that plays once, ends at rest and stays
/// on the canvas on every look holding it; a look holding nothing has none.
@Test func everyPropTheEditorOffersHasItsMove() throws {
    let props = try PlaceholderCharacter.editorChoices().props
    #expect(props == ["dumbbell", "racket"])
    for prop in props {
        for var look in Looks.squad {
            look.variants["prop"] = prop
            let figure = try PlaceholderCharacter.figure(wearing: look)
            let move = try #require(try PlaceholderCharacter.propMove(for: look), "\(prop)")
            let bound = try figure.bind(move)
            #expect(!move.loops)
            #expect(nearlyEqual(figure.pose(bound, at: move.duration), figure.restPose), "\(prop) ends at rest")
            expectOnCanvas(figure, bound, for: move.duration, "\(prop) \(move.name)")
        }
    }
    var emptyHanded = PlaceholderCharacter.lifter
    emptyHanded.variants["prop"] = nil
    #expect(try PlaceholderCharacter.propMove(for: emptyHanded) == nil)
}

/// The dumbbell is pressed overhead twice, the racket swung once across the body.
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
    let swing = try armR("racket")
    #expect(swing.min() == -84)
    #expect(swing.max() == 60)
}
