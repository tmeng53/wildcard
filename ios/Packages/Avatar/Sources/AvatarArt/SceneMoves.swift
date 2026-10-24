import AvatarDomain
import Contracts
import DesignSystem

extension SceneTheme {
    /// The sport the scene is for: what a character there trains at.
    public var sport: Sport {
        switch self {
        case .pool: .swim
        case .track: .run
        case .gym: .strength
        case .tennis: .tennis
        case .climbing: .climb
        }
    }
}

extension PlaceholderCharacter {
    /// `look` in the kit of `scene`'s sport, and that sport's move, looping: a character on the
    /// scene, training at what it is for.
    public static func sceneLoop(
        for scene: SceneTheme, look: Outfit, persona: Persona
    ) throws(AvatarError) -> (outfit: Outfit, clip: Clip) {
        let kit = try sportKits().kit(for: .sport(scene.sport))
        return (kit.dress(look), try move(for: kit, persona: persona))
    }

    /// How far into `scene`'s sport move its signature pose falls, as a share of the move: the
    /// frame a still picture of the loop shows, never whichever frame was on screen. The bar
    /// overhead, the racket through the swing, one arm up mid-stroke, legs apart mid-stride, a
    /// reach up the wall.
    public static func keyPose(for scene: SceneTheme) -> Double {
        switch scene.sport {
        case .strength: 0.47
        case .tennis: 0.61
        case .swim: 0.08
        case .run: 0.07
        case .climb: 0.25
        default: 0
        }
    }
}
