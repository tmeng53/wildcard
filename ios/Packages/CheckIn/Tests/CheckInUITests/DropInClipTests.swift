import AvatarArt
import AvatarDomain
import CheckInDomain
import Testing

/// The home's drop-in times itself by the drop clip it plays.
@Test func theDropInFollowsTheDropClip() throws {
    #expect(DropIn.land == PlaceholderCharacter.dropLands)
    let clip = try PlaceholderCharacter.drop()
    #expect(clip.duration == DropIn.dropLength)
    let fall = clip.tracks.first { $0.part.rawValue == "root" && $0.channel == .y }
    #expect(fall?.value(at: 0) == -PlaceholderCharacter.dropHeight)
}
