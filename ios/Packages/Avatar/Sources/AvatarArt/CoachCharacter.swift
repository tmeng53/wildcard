import AvatarDomain
import Foundation

/// The AI coaches' characters, by coach id, each with its own rig, art and clips in
/// `Coaches/<id>/`, bundled or downloaded (`ArtTree`). Coaches are drawn flat with no outlines,
/// unlike members, so a coach never shares members' parts or clothes. A coach the API lists without a folder here has no
/// character in this build; the screens show a stand-in for it.
public enum CoachCharacter {
    /// What a coach plays: `idle` loops, `cheer` plays once, `crying` loops (being fired), each
    /// the coach's own. The coaches' shared moves play once, from `Coaches/moves/`, unless a coach
    /// has its own of the same name: `whistle` when someone checks in, `clap` when a week's goal
    /// is reached, `pepTalk` when it gives its 战术板 line. They move the parts every coach's rig
    /// has (the whistle, its cord, a left arm in front of the body), hidden or still at rest.
    public enum Move: String, CaseIterable, Sendable {
        case idle
        case cheer
        case crying
        case whistle
        case clap
        case pepTalk = "pep-talk"

        /// Whether the move loops until another starts.
        public var loops: Bool { self == .idle || self == .crying }

        /// Whether every coach plays the same one, from `Coaches/moves/`.
        var isShared: Bool { self == .whistle || self == .clap || self == .pepTalk }
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
        var figure = try Figure(rig: rig, outfit: Outfit([:]), art: CoachArt(coach: coach))
        figure.backdrop = backdrop(coach)
        return figure
    }

    /// The colour the coach's head sits on: the backdrop its `backdrop.json` picks from
    /// `PlaceholderCharacter.backdrops`; nil without one, or for an id the list doesn't have.
    public static func backdrop(_ coach: String) -> RGBAColor? {
        guard let data = try? file(coach, "backdrop.json"), let id = try? BackdropPick.decode(data) else { return nil }
        return PlaceholderCharacter.backdrops.color(id)
    }

    public static func clip(_ move: Move, coach: String) throws(AvatarError) -> Clip {
        let own = "clips/\(move.rawValue).json"
        if !move.isShared || FileManager.default.fileExists(atPath: url(coach, own).path(percentEncoded: false)) {
            return try Clip.decode(file(coach, own))
        }
        let path = "\(sharedMoves)/\(move.rawValue).json"
        guard let data = try? Data(contentsOf: ArtTree.url(path, in: tree, bundled: root)) else {
            throw .missingFile(path)
        }
        return try Clip.decode(data)
    }

    /// The folder of the moves every coach shares; no coach is named after it.
    private static let sharedMoves = "moves"

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
