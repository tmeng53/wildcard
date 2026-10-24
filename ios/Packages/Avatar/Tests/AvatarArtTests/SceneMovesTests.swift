import AvatarArt
import AvatarDomain
import DesignSystem
import Testing

/// A character on a scene puts on its sport's kit and loops that sport's move.
@Test func aCharacterOnTheSceneTrainsAtItsSport() throws {
    let look = Outfit(["body": "peach"])
    let (outfit, clip) = try PlaceholderCharacter.sceneLoop(for: .pool, look: look, persona: .drama)
    let swim = try PlaceholderCharacter.sportKits().kit(for: .sport(.swim))
    #expect(swim.id == "swim")
    #expect(outfit == swim.dress(look))
    #expect(clip == (try PlaceholderCharacter.move(for: swim, persona: .drama)))
    #expect(clip.loops)
}
