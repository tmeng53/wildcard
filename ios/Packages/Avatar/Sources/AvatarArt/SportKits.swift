import AvatarDomain
import Contracts
import Foundation

/// What a character puts on and does for a sport: a swim cap and freestyle arms, running shoes
/// and a jog. Picking a sport turns the character into its kit for a moment; the saved look
/// never changes. Read from `kits.json`; each kit's move is `moves/sports/<id>.json`.
public struct SportKit: Hashable, Sendable, Identifiable {
    /// `swim`, `run`, ... `warmup` changes no clothes, for sports without a kit of their own.
    public let id: String
    /// The variant each slot changes to; nil takes the slot off. Slots left out stay as worn.
    public let wear: [Slot: String?]

    public init(id: String, wear: [Slot: String?]) {
        (self.id, self.wear) = (id, wear)
    }

    /// `look` in this kit. The rest of the look stays: body, hair, face, and the colors of the
    /// slots it changes when the new variant can take them (a blue tee becomes a blue tank). A
    /// slot changed to a variant that keeps its own colors, or taken off, drops the old color.
    public func dress(_ look: Outfit) -> Outfit {
        var dressed = look
        for (slot, variant) in wear {
            dressed.variants[slot] = variant
            if let variant, PlaceholderCharacter.tones(for: slot, wearing: variant) != nil { continue }
            dressed.colors[slot] = nil
        }
        return dressed
    }
}

/// Which kit each sport wears: `kits.json`. A sport takes its own entry, else its category's in
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
        return kits.first { $0.id == id } ?? SportKit(id: otherwise, wear: [:])
    }

    /// `{"version": 1, "kits": [{"id": "swim", "wear": {"hat": "swimcap", "prop": null}}],
    /// "categories": {"water": "swim"}, "sports": {}, "otherwise": "swim"}`
    public static func decode(_ data: Data) throws(AvatarError) -> SportKits {
        let file: File = try decodeJSON(data, version: currentVersion, shape: File.shape)
        let kits = file.kits.map { kit in
            SportKit(id: kit.id, wear: Dictionary(uniqueKeysWithValues: kit.wear.map { (Slot($0.key), $0.value) }))
        }
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
            // Keyed by slot, category or sport, so any key goes.
            "categories": .value, "sports": .value,
            "kits": .array(.object(["id": .value, "wear": .value])),
        ])

        let kits: [KitFile]
        let categories: [String: String]
        let sports: [String: String]
        let otherwise: String
    }

    private struct KitFile: Decodable {
        let id: String
        let wear: [String: String?]
    }
}

extension PlaceholderCharacter {
    public static func sportKits() throws(AvatarError) -> SportKits {
        try SportKits.decode(file("kits.json"))
    }

    /// A kit's move, looping, at `persona`'s tempo (`accentTempo`, the pace it plays its
    /// species' moves at): a deadpan character swims slowly, an energetic one quickly.
    public static func move(for kit: SportKit, persona: Persona) throws(AvatarError) -> Clip {
        try Clip.decode(file("moves/sports/\(kit.id).json")).atTempo(persona.accentTempo)
    }

    /// The hop a character changes into a kit in: `out` squashes it down, where the kit goes on,
    /// and `in` pops it up and lands it (`Performance.change`). It never turns or flips: the art
    /// is flat and reads badly side-on or mirrored.
    public static func kitHop() throws(AvatarError) -> (out: Clip, in: Clip) {
        (try Clip.decode(file("moves/kit-out.json")), try Clip.decode(file("moves/kit-in.json")))
    }
}
