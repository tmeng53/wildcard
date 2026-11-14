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

    /// A moment on the home the coach answers (Tracy, 2026-11-14: more than the whistle). Each
    /// plays the coach's own `clips/<raw value>.json` when it has one, else the one every coach
    /// shares in `moves/`, else `fallback`, a move every coach already plays; so a coach's own
    /// answer is art put on the server, never a build.
    public enum Moment: String, CaseIterable, Sendable {
        /// I posted a 训练.
        case myTraining = "cheer-mine"
        /// Someone posted a 健康餐.
        case healthyMeal = "thumbs-up"
        /// Someone posted a 坦白放纵餐.
        case cheatMeal = "facepalm"
        /// Someone posted a 请假条.
        case dayOff = "wave-off"
        /// The squad celebrates together (撞头, 人浪, 叠罗汉).
        case celebration = "clap-along"
        /// I accepted the coach's challenge for today.
        case challengeAccepted = "fist-pump"
        /// I stretch on my first open of the day, and the coach with me.
        case morning = "stretch"
        /// The lights went on at night.
        case lightsOn = "jolt"

        /// The move a coach without its own clip, or a shared one, plays; nil plays nothing.
        public var fallback: Move? {
            switch self {
            case .myTraining, .challengeAccepted: .cheer
            case .healthyMeal, .cheatMeal, .dayOff: .whistle
            case .celebration: .clap
            case .morning, .lightsOn: nil
            }
        }
    }

    /// The loop a coach plays standing on the home: its signature move, `clips/home.json` (马
    /// wiggling its mouse), else its idle; at night with the lights off, `clips/doze.json` if it
    /// has one.
    public static func stance(coach: String, night: Bool = false) throws(AvatarError) -> Clip {
        if night, let doze = own("doze", coach: coach) { return doze }
        if let home = own("home", coach: coach) { return home }
        return try clip(.idle, coach: coach)
    }

    /// What the coach plays at `moment`: its own clip, the shared one, else its `fallback`; nil
    /// when none of them is there.
    public static func clip(_ moment: Moment, coach: String) -> Clip? {
        if let mine = own(moment.rawValue, coach: coach) { return mine }
        let shared = ArtTree.url("\(sharedMoves)/\(moment.rawValue).json", in: tree, bundled: root)
        if let data = try? Data(contentsOf: shared), let clip = try? Clip.decode(data) { return clip }
        return moment.fallback.flatMap { try? clip($0, coach: coach) }
    }

    /// The little things the coach does now and then while nothing happens: each of its
    /// `clips/habit-*.json`, by name; none for a coach without them.
    public static func habits(coach: String) -> [Clip] {
        ArtTree.names(in: "\(coach)/clips", of: tree, bundled: root)
            .filter { $0.hasPrefix(habitPrefix) && $0.hasSuffix(".json") }
            .compactMap { own(String($0.dropLast(".json".count)), coach: coach) }
    }

    /// How a habit's file name starts.
    static let habitPrefix = "habit-"

    /// The coach's own `clips/<name>.json`, if it has one this build reads.
    private static func own(_ name: String, coach: String) -> Clip? {
        guard let data = try? Data(contentsOf: url(coach, "clips/\(name).json")) else { return nil }
        return try? Clip.decode(data)
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
