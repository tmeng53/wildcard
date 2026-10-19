import AvatarDomain
import Foundation

/// What the character editor offers beyond every bundled variant: bodies grouped by species,
/// in the order the editor shows them, and the props of this release. Read from
/// `editor.json`, so adding a species or releasing a prop is a data change. People show one
/// body and take their skin tone from the swatches.
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

    public let species: [Species]
    public let props: [String]

    public init(species: [Species], props: [String]) {
        (self.species, self.props) = (species, props)
    }

    /// The only `version` of `editor.json` this build reads.
    public static let currentVersion = 1

    /// `{"version": 1, "species": [{"id": "person", "bodies": ["peach"], "hair": true}], "props": ["dumbbell"]}`
    public static func decode(_ data: Data) throws(AvatarError) -> EditorChoices {
        let file: File
        do {
            let version = try JSONDecoder().decode(Versioned.self, from: data).version
            guard version == currentVersion else { throw AvatarError.unsupportedVersion(version) }
            file = try JSONDecoder().decode(File.self, from: data)
        } catch let error as AvatarError {
            throw error
        } catch {
            throw .malformedJSON("editor.json: \(error)")
        }
        return EditorChoices(
            species: file.species.map { Species(id: $0.id, bodies: $0.bodies, wearsHair: $0.hair ?? false) },
            props: file.props)
    }

    private struct Versioned: Decodable {
        let version: Int
    }

    private struct File: Decodable {
        let species: [SpeciesFile]
        let props: [String]
    }

    private struct SpeciesFile: Decodable {
        let id: String
        let bodies: [String]
        let hair: Bool?
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
