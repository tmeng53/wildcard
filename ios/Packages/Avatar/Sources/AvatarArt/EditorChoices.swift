import AvatarDomain
import Foundation

/// What the character editor offers beyond every bundled variant: bodies grouped by species,
/// in the order the editor shows them, the clothes on its racks with their preset colors, and the
/// props of this release. Read from `editor.json`, so adding a species or putting a piece on the
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

    /// A piece of clothing on the racks and the colors it comes in, its art's own first.
    public struct Wearable: Hashable, Sendable, Identifiable {
        public let id: String
        /// Empty when the piece keeps its art's colors.
        public let swatches: [RGBAColor]

        public init(id: String, swatches: [RGBAColor] = []) {
            (self.id, self.swatches) = (id, swatches)
        }
    }

    public let species: [Species]
    /// The pieces each clothing slot offers (`top`, `bottom`, `shoes`, `hat`, `acc`), in display
    /// order.
    public let wear: [Slot: [Wearable]]
    public let props: [String]

    public init(species: [Species], wear: [Slot: [Wearable]], props: [String]) {
        (self.species, self.wear, self.props) = (species, wear, props)
    }

    /// The only `version` of `editor.json` this build reads.
    public static let currentVersion = 2

    /// `{"version": 2, "species": [{"id": "person", "bodies": ["peach"], "hair": true}],
    /// "wear": {"top": [{"id": "warmup-tee", "swatches": ["#F4F6FA", "#1F2128"]}]}, "props": ["dumbbell"]}`
    public static func decode(_ data: Data) throws(AvatarError) -> EditorChoices {
        let file: File = try decodeJSON(data, version: currentVersion, shape: File.shape)
        var wear: [Slot: [Wearable]] = [:]
        for (slot, pieces) in file.wear {
            wear[Slot(slot)] = try pieces.map { piece throws(AvatarError) in
                let swatches = try (piece.swatches ?? []).map { hex throws(AvatarError) in
                    guard let color = RGBAColor(hex: hex) else { throw .malformedJSON("editor.json: \(hex)") }
                    return color
                }
                return Wearable(id: piece.id, swatches: swatches)
            }
        }
        return EditorChoices(
            species: file.species.map { Species(id: $0.id, bodies: $0.bodies, wearsHair: $0.hair ?? false) },
            wear: wear, props: file.props)
    }

    private struct File: Decodable {
        static let shape = JSONShape.object([
            "version": .value, "props": .value,
            // Keyed by slot, so any key goes.
            "wear": .value,
            "species": .array(.object(["id": .value, "bodies": .value, "hair": .value])),
        ])

        let species: [SpeciesFile]
        let wear: [String: [WearableFile]]
        let props: [String]
    }

    private struct SpeciesFile: Decodable {
        let id: String
        let bodies: [String]
        let hair: Bool?
    }

    private struct WearableFile: Decodable {
        let id: String
        let swatches: [String]?
    }
}

extension PlaceholderCharacter {
    public static func editorChoices() throws(AvatarError) -> EditorChoices {
        try EditorChoices.decode(file("editor.json"))
    }

    /// The colors `variant` lets a look change in `slot`: its `tones.json`, or nil when its art
    /// keeps its own colors. The base is what the editor's 原色 swatch shows.
    public static func tones(for slot: Slot, wearing variant: String) -> Tones? {
        guard let text = BundledArt().text(at: "\(slot)/\(variant)/tones.json") else { return nil }
        return try? Tones.decode(Data(text.utf8))
    }
}
