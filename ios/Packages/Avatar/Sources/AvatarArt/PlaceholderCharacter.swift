import AvatarDomain
import Foundation

/// The stand-in character until the real character design is decided: its rig, clips and
/// art, bundled with this package. Art and motion are placeholders; the file formats and
/// the player are what's real.
public enum PlaceholderCharacter {
    /// A bob, a tee, shorts and a small dumbbell.
    public static let lifter = Outfit([
        "body": "peach", "hair": "bob", "top": "tee", "bottom": "shorts", "prop": "dumbbell",
    ])
    /// A cat in a cap and tank top, with a tennis racket.
    public static let cat = Outfit([
        "body": "cat", "hat": "cap", "top": "tank", "bottom": "greenshorts", "prop": "racket",
    ])
    /// A bear in a hoodie and leggings, hands free.
    public static let bear = Outfit(["body": "bear", "top": "hoodie", "bottom": "leggings"])
    /// A headband, a jersey and a basketball.
    public static let baller = Outfit([
        "body": "tan", "hair": "buzz", "hat": "headband", "top": "jersey", "bottom": "shorts", "prop": "basketball",
    ])
    /// Four looks from the same rig: different species, hair, hats, clothes and props. Any look
    /// can play any persona's clips.
    public static let squad = [lifter, cat, bear, baller]

    /// Every variant a look can pick for `slot`, by name, sorted: what the character editor
    /// offers. Adding art is adding a folder, so this reads the bundle instead of a list.
    public static func variants(for slot: Slot) -> [String] {
        let slotFolder = folder.appendingPathComponent("art").appendingPathComponent(slot.description)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: slotFolder.path)) ?? []
        return names.filter { !$0.hasPrefix(".") }.sorted()
    }

    public static func rig() throws(AvatarError) -> Rig {
        try Rig.decode(file("rig.json"))
    }

    /// A persona's `idle` (loops) or `cheer` (plays once, for a check-in).
    public static func clip(_ name: String, persona: Persona) throws(AvatarError) -> Clip {
        try Clip.decode(file("clips/\(persona.rawValue)/\(name).json"))
    }

    public static func figure(wearing outfit: Outfit) throws(AvatarError) -> Figure {
        try Figure(rig: rig(), outfit: outfit, art: BundledArt())
    }

    static func file(_ path: String) throws(AvatarError) -> Data {
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
    func text(at path: String) -> String? {
        try? String(
            contentsOf: PlaceholderCharacter.folder.appendingPathComponent("art").appendingPathComponent(path),
            encoding: .utf8)
    }
}
