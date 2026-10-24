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
}
