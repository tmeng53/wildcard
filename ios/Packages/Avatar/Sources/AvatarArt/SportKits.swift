import AvatarDomain
import Contracts
import Foundation

/// What a character trains with for a sport: goggles and a breaststroke, a racket and a serve.
/// A kit hands the character its prop and leaves the clothes as the member saved them, so a
/// character looks the same on every screen. Read from `kits.json`. A kit with its own
/// `moves/sports/<id>.json` plays it; the others train at the signature move of their prop.
public struct SportKit: Hashable, Sendable, Identifiable {
    /// `swim`, `run`, ... `warmup` keeps the prop in hand, for sports without a kit of their own.
    public let id: String
    /// The prop the kit hands over; nil keeps the one worn.
    public let prop: String?

    public init(id: String, prop: String?) {
        (self.id, self.prop) = (id, prop)
    }

    /// `look` holding this kit's prop; everything else stays as saved.
    public func dress(_ look: Outfit) -> Outfit {
        guard let prop else { return look }
        var dressed = look
        dressed.variants["prop"] = prop
        return dressed
    }
}

/// Which kit each sport takes: `kits.json`. A sport takes its own entry, else its category's in
/// the sports list, else the warm-up. Sports and categories are data the API serves, so the
/// file may name ones the list doesn't have, and a new sport takes its category's kit.
public struct SportKits: Hashable, Sendable {
    public let kits: [SportKit]
    /// Kit ids by category id, and by sport id for single sports.
    let categories: [String: String]
    let sports: [String: String]
    /// The kit for a sport no entry covers, and for sports people name themselves.
    let otherwise: String

    /// The only `version` of `kits.json` this build reads.
    public static let currentVersion = 1

    /// The kit an activity puts on, its category read from `catalog`.
    public func kit(for activity: Activity, in catalog: SportCatalog) -> SportKit {
        let id: String
        switch activity {
        case .sport(let sport):
            id = sports[sport.rawValue] ?? catalog.entry(for: sport).flatMap { categories[$0.category] } ?? otherwise
        case .custom: id = otherwise
        }
        // `decode` checked that every id names a kit.
        return kits.first { $0.id == id } ?? SportKit(id: otherwise, prop: nil)
    }

    /// `{"version": 1, "kits": [{"id": "swim", "prop": "goggles"}],
    /// "categories": {"water": "swim"}, "sports": {}, "otherwise": "swim"}`
    public static func decode(_ data: Data) throws(AvatarError) -> SportKits {
        let file: File = try decodeJSON(data, version: currentVersion, shape: File.shape)
        let kits = file.kits.map { SportKit(id: $0.id, prop: $0.prop) }
        let ids = Set(kits.map(\.id))
        if let unknown = ([file.otherwise] + file.categories.values + file.sports.values).first(where: {
            !ids.contains($0)
        }) {
            throw .unknownKit(unknown)
        }
        if let stray = (Array(file.categories.keys) + file.sports.keys).first(where: { Sport(rawValue: $0) == nil }) {
            throw .unknownKit(stray)
        }
        return SportKits(kits: kits, categories: file.categories, sports: file.sports, otherwise: file.otherwise)
    }

    private struct File: Decodable {
        static let shape = JSONShape.object([
            "version": .value, "otherwise": .value,
            // Keyed by category or sport, so any key goes.
            "categories": .value, "sports": .value,
            "kits": .array(.object(["id": .value, "prop": .value])),
        ])

        let kits: [KitFile]
        let categories: [String: String]
        let sports: [String: String]
        let otherwise: String
    }

    private struct KitFile: Decodable {
        let id: String
        let prop: String?
    }
}

extension PlaceholderCharacter {
    public static func sportKits() throws(AvatarError) -> SportKits {
        try SportKits.decode(file("kits.json"))
    }

    /// A kit's move, looping, at `persona`'s tempo (`accentTempo`, the pace it plays its
    /// species' moves at): a deadpan character swims slowly, an energetic one quickly. A kit with
    /// a move of its own (the run kit's jog) plays it; any other loops the signature move of the
    /// prop it holds (the goggles' breaststroke, the racket's serve), which ends at rest, so it
    /// loops without a jump.
    public static func move(for kit: SportKit, persona: Persona) throws(AvatarError) -> Clip {
        if let own = try? file("moves/sports/\(kit.id).json") {
            return try Clip.decode(own).atTempo(persona.accentTempo)
        }
        guard let prop = kit.prop, var move = try propMove(for: Outfit(["prop": prop])) else {
            throw .missingFile("moves/sports/\(kit.id).json")
        }
        move.loops = true
        return try move.atTempo(persona.accentTempo)
    }

    /// The hop a character changes into a kit in: `out` squashes it down, where the kit goes on,
    /// and `in` pops it up and lands it (`Performance.change`). It never turns or flips: the art
    /// is flat and reads badly side-on or mirrored.
    public static func kitHop() throws(AvatarError) -> (out: Clip, in: Clip) {
        (try Clip.decode(file("moves/kit-out.json")), try Clip.decode(file("moves/kit-in.json")))
    }
}
