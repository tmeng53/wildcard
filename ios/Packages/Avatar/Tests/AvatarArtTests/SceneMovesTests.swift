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

/// A still picture of each scene's loop catches its widest swing at an end, never mid-way: the
/// limb that moves most is within a tenth of its reach either side.
@Test(arguments: SceneTheme.allCases)
func eachScenesKeyPoseIsAtTheEndOfItsWidestSwing(scene: SceneTheme) throws {
    let look = Outfit(["body": "peach"])
    let (_, clip) = try PlaceholderCharacter.sceneLoop(for: scene, look: look, persona: .drama)
    let time = PlaceholderCharacter.keyPose(of: clip) * clip.duration
    let swings = clip.tracks.filter { $0.channel == .rotation }.map { track in
        let values = track.keys.map(\.value)
        return (track: track, low: values.min() ?? 0, high: values.max() ?? 0)
    }
    let widest = try #require(swings.map { $0.high - $0.low }.max())
    for swing in swings where swing.high - swing.low == widest {
        let reach = (swing.track.value(at: time) - swing.low) / widest
        #expect(min(reach, 1 - reach) <= 0.1, "\(swing.track.part) is \(reach) through its swing")
    }
}
