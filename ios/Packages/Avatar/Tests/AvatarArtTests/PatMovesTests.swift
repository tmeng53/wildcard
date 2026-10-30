import AvatarArt
import AvatarDomain
import AvatarLooks
import Testing

/// The pat and every persona's way of taking it play on every look, stay on the canvas and end
/// at rest; the pat stays where the character stands.
@Test func patMovesPlayOnEveryLook() throws {
    let pat = try PlaceholderCharacter.patMove()
    let clips = try [("pat", pat)] + Persona.allCases.map { ($0.rawValue, try PlaceholderCharacter.pattedMove($0)) }
    for look in Looks.squad {
        let figure = try PlaceholderCharacter.figure(wearing: look)
        for (name, clip) in clips {
            let bound = try figure.bind(clip)
            #expect(nearlyEqual(figure.pose(bound, at: clip.duration), figure.restPose), "\(name) ends at rest")
            expectOnCanvas(
                figure, bound, for: clip.duration, name, sideways: PlaceholderCharacter.patReachSideways,
                above: PlaceholderCharacter.patReachAbove, below: PlaceholderCharacter.patReachBelow)
        }
    }
    let figure = try PlaceholderCharacter.figure(wearing: PlaceholderCharacter.lifter)
    let root = try figure.index("root")
    let bound = try figure.bind(pat)
    for step in 0...19 {
        #expect(figure.pose(bound, at: Double(step) / 10).parts[root].x == figure.restPose.parts[root].x)
    }
    #expect(PlaceholderCharacter.patContact == 0.72)
    #expect(pat.duration == 1.9)
}
