import AvatarArt
import AvatarDomain
import Testing

/// The bundled files load and fit together, so a broken edit to them fails here, not on a phone.
@Test(arguments: PlaceholderCharacter.squad)
func everyOutfitBuilds(outfit: Outfit) throws {
    let figure = try PlaceholderCharacter.figure(wearing: outfit)
    #expect(
        figure.parts.map(\.id.rawValue) == [
            "shadow", "root", "tail", "legL", "legR", "torso", "head", "eyes", "mouthSmile", "mouthOpen", "propR",
            "armL", "armR",
        ])
    // Only the bear's hands are free, and only the cat has a tail.
    #expect(figure.parts[10].art.count == (outfit == PlaceholderCharacter.bear ? 0 : 1))
    #expect(figure.parts[2].art.count == (outfit == PlaceholderCharacter.cat ? 1 : 0))
    // The open mouth waits hidden until the cheer swaps it in.
    #expect(figure.layout(figure.restPose)[9].opacity == 0)
}

@Test(arguments: ["idle", "cheer"])
func everyClipBindsToTheRig(name: String) throws {
    let figure = try PlaceholderCharacter.figure(wearing: PlaceholderCharacter.lifter)
    let clip = try PlaceholderCharacter.clip(name)
    #expect(clip.name == name)
    _ = try figure.bind(clip)
}

@Test func idleLoopsSeamlesslyAndCheerEndsAtRest() throws {
    let figure = try PlaceholderCharacter.figure(wearing: PlaceholderCharacter.lifter)
    let idle = try figure.bind(PlaceholderCharacter.clip("idle"))
    let cheer = try figure.bind(PlaceholderCharacter.clip("cheer"))
    #expect(idle.clip.loops)
    #expect(!cheer.clip.loops)
    // The idle loop's last frame is its first, so the loop has no visible jump.
    #expect(figure.pose(idle, at: idle.clip.duration - 1e-9) == figure.pose(idle, at: 0))
    // The cheer lands back in the rest pose, so handing back to idle doesn't jump either.
    #expect(figure.pose(cheer, at: cheer.clip.duration) == figure.restPose)
    // Mid-cheer the figure is in the air with its arms out.
    let peak = figure.pose(cheer, at: 0.44)
    #expect(peak.parts[1].y == -46)
    #expect(peak.parts[11].rotation == 100)
    #expect(peak.parts[12].rotation == -100)
}
