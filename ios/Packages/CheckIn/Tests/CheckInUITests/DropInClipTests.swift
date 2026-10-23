import AvatarArt
import CheckInDomain
import Testing

/// The home's drop-in times itself by the drop clip it plays.
@Test func theDropInFollowsTheDropClip() throws {
    #expect(DropIn.land == PlaceholderCharacter.dropLands)
    let clip = try PlaceholderCharacter.drop()
    #expect(clip.duration == DropIn.dropLength)
}
