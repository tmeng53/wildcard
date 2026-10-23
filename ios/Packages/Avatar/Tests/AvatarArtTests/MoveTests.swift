import AvatarArt
import AvatarDomain
import AvatarLooks
import Testing

/// Every move plays once on every look and persona, stays within its reach of the canvas and
/// ends at rest, so the idle picks up without a jump.
@Test(arguments: Persona.allCases)
func everyMovePlaysOnEveryLook(persona: Persona) throws {
    for look in Looks.squad {
        let figure = try PlaceholderCharacter.figure(wearing: look)
        for move in Move.allCases {
            let clip = try figure.bind(PlaceholderCharacter.clip(for: move, persona: persona))
            #expect(!clip.clip.loops && clip.clip.name == move.rawValue)
            #expect(nearlyEqual(figure.pose(clip, at: clip.clip.duration), figure.restPose), "\(move)")
            expectOnCanvas(
                figure, clip, for: clip.clip.duration, "\(move) \(persona.rawValue)",
                sideways: PlaceholderCharacter.moveReachSideways, above: PlaceholderCharacter.moveReachAbove)
        }
    }
}

/// A deadpan character plays a move slower than an energetic one.
@Test func movesPlayAtThePersonasTempo() throws {
    let deadpan = try PlaceholderCharacter.clip(for: .wave, persona: .deadpan)
    let energetic = try PlaceholderCharacter.clip(for: .wave, persona: .energetic)
    #expect(abs(deadpan.duration - 1.3 / 0.7) < 1e-9)
    #expect(abs(energetic.duration - 1.3 / 1.4) < 1e-9)
}
