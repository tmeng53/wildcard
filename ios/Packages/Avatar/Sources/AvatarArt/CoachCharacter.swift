import AvatarDomain
import Foundation

/// The AI coaches' characters, by coach id, each with its own rig, art and clips in
/// `Coaches/<id>/`, bundled or downloaded (`ArtTree`). Coaches are drawn flat with no outlines, unlike members, so a coach never
/// shares members' parts or clothes. A coach the API lists without a folder here has no
/// character in this build; the screens show a stand-in for it.
public enum CoachCharacter {
    /// What a coach plays: `idle` loops, `cheer` plays once, `crying` loops (being fired).
    public enum Move: String, CaseIterable, Sendable {
        case idle
        case cheer
        case crying
    }

    /// Whether this build has the coach's character.
    public static func exists(_ coach: String) -> Bool {
        FileManager.default.fileExists(atPath: url(coach, "rig.json").path(percentEncoded: false))
    }

    /// The coaches this build draws, by id, sorted.
    public static var bundled: [String] {
        ArtTree.names(in: "", of: tree, bundled: root).filter(exists)
    }

    public static func figure(_ coach: String) throws(AvatarError) -> Figure {
        let rig = try Rig.decode(file(coach, "rig.json"))
        return try Figure(rig: rig, outfit: Outfit([:]), art: CoachArt(coach: coach))
    }

    public static func clip(_ move: Move, coach: String) throws(AvatarError) -> Clip {
        try Clip.decode(file(coach, "clips/\(move.rawValue).json"))
    }

    private static func file(_ coach: String, _ path: String) throws(AvatarError) -> Data {
        guard let data = try? Data(contentsOf: url(coach, path)) else {
            throw .missingFile("\(coach)/\(path)")
        }
        return data
    }

    /// The file at `path` in `coach`'s folder: downloaded, else bundled.
    fileprivate static func url(_ coach: String, _ path: String) -> URL {
        ArtTree.url("\(coach)/\(path)", in: tree, bundled: root)
    }

    private static let tree = "coaches"

    /// The copied `Coaches` folder inside this package's resource bundle.
    static var root: URL {
        (Bundle.module.resourceURL ?? Bundle.module.bundleURL).appendingPathComponent("Coaches")
    }
}

/// Reads a coach's art from its folder.
private struct CoachArt: ArtSource {
    let coach: String

    func text(at path: String) -> String? {
        try? String(contentsOf: CoachCharacter.url(coach, "art/\(path)"), encoding: .utf8)
    }
}
