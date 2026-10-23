import AvatarArt
import AvatarDomain
import AvatarLooks
import Testing

/// Every reaction move plays once on every look at every persona's tempo, stays on the canvas and
/// ends at rest, so it hands back to idle without a jump.
@Test(arguments: Persona.allCases)
func reactionsPlayOnEveryLook(persona: Persona) throws {
    for id in PlaceholderCharacter.reactionMoves {
        let clip = try #require(PlaceholderCharacter.reactionMove(id, persona: persona))
        for look in Looks.squad {
            let figure = try PlaceholderCharacter.figure(wearing: look)
            let bound = try figure.bind(clip)
            #expect(nearlyEqual(figure.pose(bound, at: clip.duration), figure.restPose), "\(id) ends at rest")
            expectOnCanvas(figure, bound, for: clip.duration, "\(id) \(persona.rawValue)")
        }
    }
}

/// Each persona reacts its own way: every persona's version of a move differs from the others,
/// 淡人 moves least, and the shared move is there for every persona.
@Test func personasReactTheirOwnWay() throws {
    let figure = try PlaceholderCharacter.figure(wearing: PlaceholderCharacter.lifter)
    let root = try figure.index("root")
    for id in PlaceholderCharacter.reactionMoves {
        let clips = try Persona.allCases.map {
            try #require(PlaceholderCharacter.reactionMove(id, persona: $0), "\(id) \($0)")
        }
        #expect(Set(clips.map(\.duration)).count == Persona.allCases.count, "\(id)")
        func height(_ clip: Clip) throws -> Double {
            let bound = try figure.bind(clip)
            return (0...Int(clip.duration * 100)).map { -figure.pose(bound, at: Double($0) / 100).parts[root].y }.max()
                ?? 0
        }
        let heights = try clips.map(height)
        #expect(heights[0] <= (heights.dropFirst().max() ?? 0), "\(id): 淡人 jumps lowest")
    }
}

/// The faces the reactions borrow stay hidden at rest and show only in their move: the O of a
/// shock, the drool drop, a pout's V brows, 💢, steam, puffed cheeks and frown.
@Test func reactionFacesShowOnlyInTheirMove() throws {
    let figure = try PlaceholderCharacter.figure(wearing: PlaceholderCharacter.lifter)
    let rest = figure.layout(figure.restPose)
    for part in [
        "mouthGasp", "drool", "puff", "browsMad", "vein", "steamL", "steamR", "stars", "gloom", "bang", "squirtL",
        "squirtR", "heart", "heartL", "heartR", "sparkle", "flexL", "flexR", "muscleL", "muscleR",
    ] as [PartID] {
        #expect(rest[try figure.index(part)].opacity == 0, "\(part)")
    }
    func opacity(_ part: PartID, in id: String, at time: Double) throws -> Double {
        let bound = try figure.bind(try #require(PlaceholderCharacter.reactionMove(id)))
        return figure.layout(figure.pose(bound, at: time))[try figure.index(part)].opacity
    }
    #expect(try opacity("mouthGasp", in: "shocked", at: 0.6) == 1)
    #expect(try opacity("mouthSmile", in: "shocked", at: 0.6) == 0)
    #expect(try opacity("drool", in: "drool", at: 1.3) == 1)
    #expect(try opacity("stars", in: "drool", at: 1.0) == 1)
    #expect(try opacity("eyes", in: "drool", at: 1.0) == 0)
    #expect(try opacity("bang", in: "shocked", at: 0.6) == 1)
    #expect(try opacity("gloom", in: "shocked", at: 0.6) == 1)
    #expect(try opacity("squirtL", in: "laugh-bend", at: 1.0) == 1)
    #expect(try opacity("heart", in: "heart", at: 1.0) == 1)
    #expect(try opacity("muscleR", in: "flex", at: 1.0) == 1)
    #expect(try opacity("flexR", in: "flex", at: 1.0) == 1)
    #expect(try opacity("armR", in: "flex", at: 1.0) == 0)
    #expect(try opacity("sparkle", in: "chin-up", at: 1.3) == 1)
    #expect(try opacity("puff", in: "pout", at: 1.0) == 1)
    #expect(try opacity("mouthSad", in: "pout", at: 1.0) == 1)
    #expect(try opacity("browsMad", in: "pout", at: 1.0) == 1)
    #expect(try opacity("brows", in: "pout", at: 1.0) == 0)
    #expect(try opacity("vein", in: "pout", at: 1.0) == 1)
    #expect(try opacity("steamL", in: "pout", at: 1.1) == 1)
}

/// Every brows variant draws an angry `mad` pair in its own style and color, for a pout.
@Test func everyBrowsHaveAMadPair() throws {
    for brows in PlaceholderCharacter.variants(for: "brows") {
        let figure = try PlaceholderCharacter.figure(wearing: Outfit(["body": "peach", "brows": brows]))
        #expect(try figure.part("browsMad").art.count == 1, "\(brows)")
        #expect(try figure.part("browsMad").art != figure.part("browsSad").art, "\(brows)")
    }
}
