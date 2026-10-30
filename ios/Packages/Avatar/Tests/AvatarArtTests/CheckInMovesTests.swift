import AvatarArt
import AvatarDomain
import AvatarLooks
import Testing

/// Food shows only on a look dressed for a meal, in place of the hand prop; the lift holds the
/// dumbbell, and the rest of the look stays.
@Test func onlyMealsHoldFood() throws {
    for move in CheckInMove.allCases {
        let look = PlaceholderCharacter.dressed(Looks.cat, for: move)
        let figure = try PlaceholderCharacter.figure(wearing: look)
        let eats = move == .healthyMeal || move == .treatMeal
        #expect(try figure.part("food0").art.isEmpty == !eats, "\(move)")
        #expect(try figure.part("propR").art.isEmpty == (move != .workout), "\(move)")
        #expect(look.variants["hat"] == Looks.cat.variants["hat"])
    }
    #expect(PlaceholderCharacter.dressed(Looks.cat, for: .workout).variants["prop"] == "dumbbell")
    let standing = try PlaceholderCharacter.figure(wearing: Looks.cat)
    #expect(try ["food0", "food1", "food2"].allSatisfy { try standing.part($0).art.isEmpty })
    // The bitten states wait hidden until a bite swaps them in.
    for part in ["food1", "food2"] as [PartID] {
        #expect(standing.layout(standing.restPose)[try standing.index(part)].opacity == 0)
    }
}

/// Each check-in move plays once on every look and persona, stays on the canvas and ends where
/// the body started, so idle takes over without a jump. Food and the chewing mouth may end
/// changed: the food is gone and the look puts its own prop back.
@Test(arguments: Persona.allCases)
func checkInMovesPlayOnceOnEveryLook(persona: Persona) throws {
    for move in CheckInMove.allCases {
        let clip = try PlaceholderCharacter.clip(for: move, persona: persona)
        #expect(!clip.loops, "\(move)")
        for look in Looks.squad {
            let figure = try PlaceholderCharacter.figure(wearing: PlaceholderCharacter.dressed(look, for: move))
            let bound = try figure.bind(clip)
            expectOnCanvas(figure, bound, for: clip.duration, "\(move) \(persona.rawValue)")
            let end = figure.pose(bound, at: clip.duration)
            let free: Set<PartID> = ["food0", "food1", "food2", "propR", "mouthOpen", "mouthSmile"]
            for (index, part) in figure.parts.enumerated() where !free.contains(part.id) {
                let gaps = Channel.allCases.map { abs(end.parts[index][$0] - figure.restPose.parts[index][$0]) }
                #expect(gaps.allSatisfy { $0 < 1e-6 }, "\(move) \(part.id) \(persona.rawValue)")
            }
        }
    }
}
