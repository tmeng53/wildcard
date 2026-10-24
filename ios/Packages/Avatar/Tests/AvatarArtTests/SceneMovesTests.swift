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

/// A still picture of each scene's loop shows its sport's signature pose, inside the move.
@Test func eachSceneHasAKeyPoseInsideItsMove() {
    #expect(PlaceholderCharacter.keyPose(for: .gym) == 0.47)
    #expect(PlaceholderCharacter.keyPose(for: .tennis) == 0.61)
    #expect(PlaceholderCharacter.keyPose(for: .pool) == 0.08)
    #expect(PlaceholderCharacter.keyPose(for: .track) == 0.07)
    #expect(PlaceholderCharacter.keyPose(for: .climbing) == 0.25)
}
