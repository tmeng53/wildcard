import Contracts
import DesignSystem
import Foundation

/// Each squad's scene as the app last read it, kept on this phone so 今天 opens on it when the
/// server is slow or out of reach, rather than on the gym and then switching.
enum KeptScene {
    private struct Saved: Codable {
        var version = 1
        let scene: String
    }

    private static let prefix = "scene."

    private static func key(_ squad: SquadID) -> String { prefix + squad.description }

    static func save(_ scene: SceneTheme, of squad: SquadID) {
        guard let data = try? JSONEncoder().encode(Saved(scene: scene.rawValue)) else { return }
        UserDefaults.standard.set(data, forKey: key(squad))
    }

    static func scene(of squad: SquadID) -> SceneTheme? {
        guard let data = UserDefaults.standard.data(forKey: key(squad)),
            let saved = try? JSONDecoder().decode(Saved.self, from: data), saved.version == 1
        else { return nil }
        return SceneTheme(rawValue: saved.scene)
    }

    /// Signing out forgets every squad's scene with the rest of what the phone kept.
    static func forgetAll() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }
}
