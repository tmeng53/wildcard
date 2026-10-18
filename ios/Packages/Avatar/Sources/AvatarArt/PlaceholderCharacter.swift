import AvatarDomain
import Foundation

/// The stand-in character until the real character design is decided: its rig, clips and
/// art, bundled with this package. Art and motion are placeholders; the file formats and
/// the player are what's real.
public enum PlaceholderCharacter {
    /// Short-sleeved tee, shorts and a small dumbbell in the right hand.
    public static let tee = Outfit(["hair": "short", "top": "tee", "bottom": "shorts", "prop": "dumbbell"])
    /// Hoodie and shorts, hands free.
    public static let hoodie = Outfit(["hair": "short", "top": "hoodie", "bottom": "shorts"])

    public static func rig() throws(AvatarError) -> Rig {
        try Rig.decode(file("rig.json"))
    }

    /// `idle` (loops) or `cheer` (plays once, for a check-in).
    public static func clip(_ name: String) throws(AvatarError) -> Clip {
        try Clip.decode(file("clips/\(name).json"))
    }

    public static func figure(wearing outfit: Outfit) throws(AvatarError) -> Figure {
        try Figure(rig: rig(), outfit: outfit, art: BundledArt())
    }

    private static func file(_ path: String) throws(AvatarError) -> Data {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(path)) else { throw .missingFile(path) }
        return data
    }

    /// The copied `Placeholder` folder inside this package's resource bundle.
    static var folder: URL {
        (Bundle.module.resourceURL ?? Bundle.module.bundleURL).appendingPathComponent("Placeholder")
    }
}

/// Reads art files from the placeholder's folder in this package's bundle.
struct BundledArt: ArtSource {
    func svg(at path: String) -> String? {
        try? String(
            contentsOf: PlaceholderCharacter.folder.appendingPathComponent("art").appendingPathComponent(path),
            encoding: .utf8)
    }
}
