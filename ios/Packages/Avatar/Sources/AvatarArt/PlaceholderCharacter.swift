import AvatarDomain
import Foundation

/// The stand-in character until the real character design is decided: its rig, clips and
/// art, bundled with this package. Art and motion are placeholders; the file formats and
/// the player are what's real.
public enum PlaceholderCharacter {
    /// A bob, soft brows, rosy cheeks, a tee, shorts and a small dumbbell.
    public static let lifter = Outfit([
        "body": "peach", "hair": "bob", "brows": "soft", "cheeks": "rosy", "top": "tee", "bottom": "shorts",
        "prop": "dumbbell",
    ])

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

    /// A persona's `idle` (loops), `cheer` (plays once, for a check-in) or `welcome` (plays once
    /// at 上场: teammates cheering a new member in, one after another, and the newcomer on landing).
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
