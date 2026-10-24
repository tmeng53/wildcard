import AvatarDomain
import Contracts
import DesignSystem

extension SceneTheme {
    /// The sport the scene is for: what a character there trains at.
    public var sport: Sport {
        switch self {
        case .pool: "swim"
        case .track: "run"
        case .gym: "strength"
        case .tennis: "tennis"
        case .climbing: "climb"
        }
    }
}

extension PlaceholderCharacter {
    /// `look` in the kit of `scene`'s sport, and that sport's move, looping: a character on the
    /// scene, training at what it is for.
    public static func sceneLoop(
        for scene: SceneTheme, look: Outfit, persona: Persona, in catalog: SportCatalog
    ) throws(AvatarError) -> (outfit: Outfit, clip: Clip) {
        let kit = try sportKits().kit(for: .sport(scene.sport), in: catalog)
        return (kit.dress(look), try move(for: kit, persona: persona))
    }

    /// How far into a sport's move its signature pose falls, as a share of the move: the frame
    /// a still picture of the loop shows, never whichever frame was on screen. It is where the
    /// move's widest swing reaches its end farthest from rest: the bell overhead, the racket
    /// through the swing, the arms out mid-stroke.
    public static func keyPose(of clip: Clip) -> Double {
        let swings = clip.tracks.filter { $0.channel == .rotation }
        func width(_ track: Clip.Track) -> Double {
            let values = track.keys.map(\.value)
            return (values.max() ?? 0) - (values.min() ?? 0)
        }
        guard clip.duration > 0, let widest = swings.max(by: { width($0) < width($1) }),
            let end = widest.keys.max(by: { abs($0.value) < abs($1.value) })
        else { return 0 }
        return end.time / clip.duration
    }
}
