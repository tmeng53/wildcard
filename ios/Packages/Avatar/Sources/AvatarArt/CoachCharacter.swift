import AvatarDomain
import Foundation

/// The AI coaches' characters, by coach id, each with its own rig, art and clips in
/// `Coaches/<id>/`. Coaches are drawn flat with no outlines, unlike members, so a coach never
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
        FileManager.default.fileExists(atPath: folder(coach).appendingPathComponent("rig.json").path)
    }

    /// The coaches this build draws, by id, sorted.
    public static var bundled: [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return names.filter(exists).sorted()
    }

    public static func figure(_ coach: String) throws(AvatarError) -> Figure {
        let rig = try Rig.decode(file(coach, "rig.json"))
        return try Figure(rig: rig, outfit: Outfit([:]), art: CoachArt(folder: folder(coach)))
    }

    public static func clip(_ move: Move, coach: String) throws(AvatarError) -> Clip {
        try Clip.decode(file(coach, "clips/\(move.rawValue).json"))
    }

    private static func file(_ coach: String, _ path: String) throws(AvatarError) -> Data {
        guard let data = try? Data(contentsOf: folder(coach).appendingPathComponent(path)) else {
            throw .missingFile("\(coach)/\(path)")
        }
        return data
    }

    private static func folder(_ coach: String) -> URL { root.appendingPathComponent(coach) }

    /// The copied `Coaches` folder inside this package's resource bundle.
    private static var root: URL {
        (Bundle.module.resourceURL ?? Bundle.module.bundleURL).appendingPathComponent("Coaches")
    }
}

/// Reads a coach's art from its folder.
private struct CoachArt: ArtSource {
    let folder: URL

    func text(at path: String) -> String? {
        try? String(contentsOf: folder.appendingPathComponent("art").appendingPathComponent(path), encoding: .utf8)
    }
}
