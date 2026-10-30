import AvatarDomain
import Foundation

/// What the character editor offers beyond every bundled variant: bodies grouped by species,
/// in the order the editor shows them, the stores of its shopping street, the clothes on their
/// racks with their preset colors, and the props of this release. Read from `editor.json`, so adding a species or putting a piece on the
/// racks is a data change; bundled art the lists leave out (a swim cap only a sport's kit wears)
/// stays hidden. People show one body and take their skin tone from the swatches.
public struct EditorChoices: Hashable, Sendable {
    public struct Species: Hashable, Sendable, Identifiable {
        /// `person`, `cat`, ... Its display name is UI copy, in the editor's String Catalog.
        public let id: String
        public let bodies: [String]
        /// People wear hair; animals wear their coat.
        public let wearsHair: Bool

        public init(id: String, bodies: [String], wearsHair: Bool = false) {
            (self.id, self.bodies, self.wearsHair) = (id, bodies, wearsHair)
        }
    }

    /// A store on the editor's shopping street. Its names, line and how it opens are UI copy,
    /// in the editor's String Catalog; its badge is `stores/<id>.svg`.
    public struct Store: Hashable, Sendable, Identifiable {
        /// `warmup`, `lap`, ...: the prefix of its pieces' ids.
        public let id: String
        /// Whether every member can shop there. For now only WARM-UP is; the others open with
        /// check-ins once the catalog keeps who unlocked what.
        public let isOpen: Bool

        public init(id: String, isOpen: Bool = false) {
            (self.id, self.isOpen) = (id, isOpen)
        }
    }

    /// A piece of clothing on a store's rack and the colors it comes in, its art's own first.
    public struct Wearable: Hashable, Sendable, Identifiable {
        public let id: String
        /// The store whose rack it hangs on.
        public let store: String
        /// Empty when the piece keeps its art's colors.
        public let swatches: [RGBAColor]

        public init(id: String, store: String, swatches: [RGBAColor] = []) {
            (self.id, self.store, self.swatches) = (id, store, swatches)
        }
    }

    public let species: [Species]
    /// The shopping street's stores, in the order it shows them.
    public let stores: [Store]
    /// The pieces each clothing slot offers (`top`, `bottom`, `shoes`, `hat`, `acc`), in display
    /// order.
    public let wear: [Slot: [Wearable]]
    public let props: [String]

    public init(species: [Species], stores: [Store], wear: [Slot: [Wearable]], props: [String]) {
        (self.species, self.stores, self.wear, self.props) = (species, stores, wear, props)
    }

    /// The only `version` of `editor.json` this build reads.
    public static let currentVersion = 3

    /// `{"version": 3, "species": [{"id": "person", "bodies": ["peach"], "hair": true}],
    /// "stores": [{"id": "warmup", "open": true}, {"id": "lap"}],
    /// "wear": {"top": [{"id": "warmup-tee", "store": "warmup", "swatches": ["#F4F6FA", "#1F2128"]}]},
    /// "props": ["dumbbell"]}`. Every piece hangs in a store the list has.
    public static func decode(_ data: Data) throws(AvatarError) -> EditorChoices {
        let file: File = try decodeJSON(data, version: currentVersion, shape: File.shape)
        let stores = file.stores.map { Store(id: $0.id, isOpen: $0.open ?? false) }
        var wear: [Slot: [Wearable]] = [:]
        for (slot, pieces) in file.wear {
            wear[Slot(slot)] = try pieces.map { piece throws(AvatarError) in
                guard stores.contains(where: { $0.id == piece.store }) else {
                    throw .malformedJSON("editor.json: \(piece.id) hangs in no store")
                }
                let swatches = try (piece.swatches ?? []).map { hex throws(AvatarError) in
                    guard let color = RGBAColor(hex: hex) else { throw .malformedJSON("editor.json: \(hex)") }
                    return color
                }
                return Wearable(id: piece.id, store: piece.store, swatches: swatches)
            }
        }
        return EditorChoices(
            species: file.species.map { Species(id: $0.id, bodies: $0.bodies, wearsHair: $0.hair ?? false) },
            stores: stores, wear: wear, props: file.props)
    }

    private struct File: Decodable {
        static let shape = JSONShape.object([
            "version": .value, "props": .value,
            "stores": .array(.object(["id": .value, "open": .value])),
            // Keyed by slot, so any key goes.
            "wear": .value,
            "species": .array(.object(["id": .value, "bodies": .value, "hair": .value])),
        ])

        let species: [SpeciesFile]
        let stores: [StoreFile]
        let wear: [String: [WearableFile]]
        let props: [String]
    }

    private struct StoreFile: Decodable {
        let id: String
        let open: Bool?
    }

    private struct SpeciesFile: Decodable {
        let id: String
        let bodies: [String]
        let hair: Bool?
    }

    private struct WearableFile: Decodable {
        let id: String
        let store: String
        let swatches: [String]?
    }
}

extension PlaceholderCharacter {
    public static func editorChoices() throws(AvatarError) -> EditorChoices {
        try EditorChoices.decode(file("editor.json"))
    }

    /// A store's badge, `stores/<id>.svg`.
    public static func storeBadge(_ store: String) throws(AvatarError) -> Artwork {
        let path = "stores/\(store).svg"
        guard let svg = String(bytes: try file(path), encoding: .utf8) else { throw .missingFile(path) }
        return try Artwork.read(svg: svg, path: path)
    }

    /// The colors `variant` lets a look change in `slot`: its `tones.json`, or nil when its art
    /// keeps its own colors. The base is what the editor's 原色 swatch shows.
    public static func tones(for slot: Slot, wearing variant: String) -> Tones? {
        guard let text = BundledArt().text(at: "\(slot)/\(variant)/tones.json") else { return nil }
        return try? Tones.decode(Data(text.utf8))
    }
}
