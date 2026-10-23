import AvatarArt
import AvatarDomain
import AvatarLooks
import Testing

private func homePoses(_ persona: Persona) throws -> [Clip] {
    [
        try PlaceholderCharacter.sitting(persona: persona), try PlaceholderCharacter.holdingSign(persona: persona),
        try PlaceholderCharacter.sleeping(persona: persona),
    ]
}

/// Sitting, the sign and sleeping loop without a jump and stay on the canvas, on every look and
/// persona, with the hand prop put away.
@Test(arguments: Persona.allCases)
func homePosesPlayOnEveryLook(persona: Persona) throws {
    for look in Looks.squad {
        let figure = try PlaceholderCharacter.figure(wearing: look)
        for clip in try homePoses(persona) {
            let bound = try figure.bind(clip)
            #expect(clip.loops)
            #expect(nearlyEqual(figure.pose(bound, at: clip.duration - 1e-9), figure.pose(bound, at: 0)))
            #expect(try figure.layout(figure.pose(bound, at: 0.5))[figure.index("propR")].opacity == 0)
            expectOnCanvas(figure, bound, for: clip.duration, "\(clip.name) \(persona.rawValue)")
        }
    }
}

/// Sitting and sleeping bring the body down to the floor; asleep, the eyes are shut and the
/// smile gone. Holding the sign, both hands reach out to the card's lower corners.
@Test func homePosesSitSleepAndHold() throws {
    let figure = try PlaceholderCharacter.figure(wearing: PlaceholderCharacter.lifter)
    let (root, eyes, smile) = (try figure.index("root"), try figure.index("eyes"), try figure.index("mouthSmile"))
    let (armL, armR) = (try figure.index("armL"), try figure.index("armR"))
    for clip in [try PlaceholderCharacter.sitting(persona: .drama), try PlaceholderCharacter.sleeping(persona: .drama)]
    {
        #expect(figure.pose(try figure.bind(clip), at: 1).parts[root].y == 14, "\(clip.name)")
    }
    let asleep = figure.pose(try figure.bind(PlaceholderCharacter.sleeping(persona: .drama)), at: 1)
    #expect(asleep.parts[eyes].scaleY < 0.2)
    #expect(figure.layout(asleep)[smile].opacity == 0)
    let sign = try figure.bind(PlaceholderCharacter.holdingSign(persona: .drama))
    for frame in 0...Int(sign.clip.duration * 50) {
        let pose = figure.pose(sign, at: Double(frame) / 50)
        #expect(pose.parts[armL].rotation > 10 && pose.parts[armR].rotation < -10)
    }
}
