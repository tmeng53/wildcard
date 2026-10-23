import AvatarArt
import AvatarDomain
import AvatarLooks
import Testing

/// 我's desk: the laptop and desk stand in front of everything, only when the look sits at it,
/// and the hand prop comes off.
@Test func theDeskShowsOnlyAtTheDesk() throws {
    let standing = try PlaceholderCharacter.figure(wearing: Looks.cat)
    let seated = try PlaceholderCharacter.figure(wearing: PlaceholderCharacter.atDesk(Looks.cat))
    #expect(try standing.part("desk").art.isEmpty)
    #expect(try seated.part("desk").art.count == 1)
    #expect(try seated.part("propR").art.isEmpty)
    #expect(seated.parts.last?.id == "desk")
    #expect(PlaceholderCharacter.atDesk(Looks.cat).variants["hat"] == "cap")
}

/// Typing and crying loop without a jump and stay on the canvas, on every look and persona.
@Test(arguments: Persona.allCases)
func meMovesPlayOnEveryLook(persona: Persona) throws {
    for look in Looks.squad {
        let atDesk = try PlaceholderCharacter.figure(wearing: PlaceholderCharacter.atDesk(look))
        let standing = try PlaceholderCharacter.figure(wearing: look)
        for (figure, clip) in [
            (atDesk, try PlaceholderCharacter.typing(persona: persona)),
            (standing, try PlaceholderCharacter.teary(persona: persona)),
        ] {
            let bound = try figure.bind(clip)
            #expect(clip.loops)
            #expect(abs(clip.duration * persona.accentTempo - (clip.name == "typing" ? 4 : 3.2)) < 1e-9)
            #expect(nearlyEqual(figure.pose(bound, at: clip.duration - 1e-9), figure.pose(bound, at: 0)))
            expectOnCanvas(figure, bound, for: clip.duration, "\(clip.name) \(persona.rawValue)")
        }
    }
}

/// Typing rises up to peek over the screen once a loop, and comes back down.
@Test func typingPeeksOverTheScreen() throws {
    let figure = try PlaceholderCharacter.figure(wearing: PlaceholderCharacter.atDesk(PlaceholderCharacter.lifter))
    let typing = try figure.bind(PlaceholderCharacter.typing(persona: .drama))
    let root = try figure.index("root")
    let heights = (0...Int(typing.clip.duration * 100)).map {
        figure.pose(typing, at: Double($0) / 100).parts[root].y
    }
    #expect(heights.min() ?? 0 < -9)
    #expect(heights.first == 0 && abs(heights.last ?? 1) < 0.1)
}

/// Crying swaps the face to worried brows and a frown for the whole loop, and each tear wells
/// up, rolls down and is gone again by the end. At rest the sad face stays hidden.
@Test func tearsWellUpAndRollDown() throws {
    let figure = try PlaceholderCharacter.figure(wearing: PlaceholderCharacter.lifter)
    let teary = try figure.bind(PlaceholderCharacter.teary(persona: .drama))
    let rest = figure.layout(figure.restPose)
    for part in ["browsSad", "mouthSad", "tearL", "tearR"] as [PartID] {
        #expect(rest[try figure.index(part)].opacity == 0, "\(part)")
    }
    func shown(_ part: PartID, at time: Double) throws -> (opacity: Double, scale: Double, y: Double) {
        let pose = figure.pose(teary, at: time / Persona.drama.accentTempo)
        let index = try figure.index(part)
        return (figure.layout(pose)[index].opacity, pose.parts[index].scaleY, pose.parts[index].y)
    }
    for time in [0.0, 1.0, 2.0, 3.0] {
        #expect(try shown("brows", at: time).opacity == 0)
        #expect(try shown("mouthSmile", at: time).opacity == 0)
        #expect(try shown("browsSad", at: time).opacity == 1)
        #expect(try shown("mouthSad", at: time).opacity == 1)
    }
    #expect(try shown("tearL", at: 0).scale == 0)
    #expect(try shown("tearL", at: 1.2).scale == 1)
    #expect(try shown("tearL", at: 2.3).y > 20)
    #expect(try shown("tearR", at: 0.4).scale == 0)
}

/// Every brows variant draws a worried `sad` pair in its own style and color, for crying.
@Test func everyBrowsHaveASadPair() throws {
    for brows in PlaceholderCharacter.variants(for: "brows") {
        let figure = try PlaceholderCharacter.figure(wearing: Outfit(["body": "peach", "brows": brows]))
        #expect(try figure.part("browsSad").art.count == 1, "\(brows)")
        #expect(try figure.part("browsSad").art != figure.part("brows").art, "\(brows)")
    }
}
