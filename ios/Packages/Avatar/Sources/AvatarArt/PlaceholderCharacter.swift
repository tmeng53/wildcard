import AvatarDomain
import Foundation

/// The stand-in character until the real character design is decided: its rig, clips and
/// art, bundled with this package. Art and motion are placeholders; the file formats and
/// the player are what's real.
public enum PlaceholderCharacter {
    /// A bob, soft brows, rosy cheeks, WARM-UP's tee and shorts and a small dumbbell.
    public static let lifter = Outfit([
        "body": "peach", "hair": "bob", "brows": "soft", "cheeks": "rosy", "top": "warmup-tee",
        "bottom": "warmup-shorts", "prop": "dumbbell",
    ])

    /// Every variant a look can pick for `slot`, by name, sorted: what the character editor
    /// offers. Adding art is adding a folder, bundled or downloaded (`ArtTree`), so this reads
    /// the folders instead of a list.
    public static func variants(for slot: Slot) -> [String] {
        ArtTree.names(in: "art/\(slot)", of: tree, bundled: folder)
    }

    public static func rig() throws(AvatarError) -> Rig {
        try Rig.decode(file("rig.json"))
    }

    /// A persona's `idle` (loops), `cheer` (plays once, for a check-in) or `welcome` (plays once
    /// at 上场: teammates cheering a new member in, one after another, and the newcomer on landing).
    public static func clip(_ name: String, persona: Persona) throws(AvatarError) -> Clip {
        try Clip.decode(file("clips/\(persona.rawValue)/\(name).json"))
    }

    /// The character in `outfit`, as far as this build has its art: see `drawable(_:)`.
    public static func figure(wearing outfit: Outfit) throws(AvatarError) -> Figure {
        try Figure(rig: rig(), outfit: drawable(outfit), art: PlaceholderArt())
    }

    /// `outfit` as this build can draw it. A variant without art here, such as a piece retired
    /// since the look was saved or released after this build, gives way to what the rig draws
    /// there by default, and a color is dropped when what's drawn can't take it.
    public static func drawable(_ outfit: Outfit) throws(AvatarError) -> Outfit {
        let art = PlaceholderArt()
        var drawn = outfit
        drawn.variants = outfit.variants.filter { slot, variant in
            FileManager.default.fileExists(
                atPath: ArtTree.url("art/\(slot)/\(variant)", in: tree, bundled: folder).path(percentEncoded: false))
        }
        let worn = try rig().defaults.merging(drawn.variants) { _, picked in picked }
        drawn.colors = outfit.colors.filter { slot, _ in
            worn[slot].map { art.text(at: "\(slot)/\($0)/tones.json") != nil } ?? false
        }
        return drawn
    }

    /// The file at `path`: downloaded, else bundled (`ArtTree`).
    static func file(_ path: String) throws(AvatarError) -> Data {
        guard let data = try? Data(contentsOf: ArtTree.url(path, in: tree, bundled: folder)) else {
            throw .missingFile(path)
        }
        return data
    }

    /// The placeholder's part of the art tree.
    static let tree = "avatar"

    /// The copied `Placeholder` folder inside this package's resource bundle.
    static var folder: URL {
        (Bundle.module.resourceURL ?? Bundle.module.bundleURL).appendingPathComponent("Placeholder")
    }
}

/// Reads the placeholder's art files: downloaded, else bundled (`ArtTree`).
struct PlaceholderArt: ArtSource {
    func text(at path: String) -> String? {
        try? String(
            contentsOf: ArtTree.url("art/\(path)", in: PlaceholderCharacter.tree, bundled: PlaceholderCharacter.folder),
            encoding: .utf8)
    }
}
