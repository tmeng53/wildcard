import Foundation

/// Everything the catalog (`GET /public/catalog`) holds that this build reads: data the app shows
/// that lives in the database, so it changes without an app release.
public struct AppCatalog: Hashable, Sendable {
    /// Every sport the pickers show.
    public let sports: SportCatalog
    /// The ready-made 请假条 lines rolled when the AI can't write.
    public let diceLines: [CatalogNames]
    /// The 商店街 of a member who hasn't trained yet, for an editor opened before the member's own
    /// street is read (signing up, the sample squad): the free stores and their starters. A store
    /// or piece on a switch is left out, since only the server says whether a switch is on.
    public let starterStock: StreetStock
    /// The art files put over the ones this build bundles.
    public let art: ArtManifest
    /// Every scene, in the picker's order: a scene added since this build takes its names and
    /// colours from here.
    public let scenes: [CatalogScene]
    /// The global switches, such as what only the public beta has (`BetaFeature`).
    public let switches: [CatalogSwitch]

    public init(
        sports: SportCatalog, diceLines: [CatalogNames], starterStock: StreetStock = .empty,
        art: ArtManifest = .none, scenes: [CatalogScene] = [], switches: [CatalogSwitch] = []
    ) {
        (self.sports, self.diceLines, self.starterStock, self.art) = (sports, diceLines, starterStock, art)
        (self.scenes, self.switches) = (scenes, switches)
    }

    /// Nothing at all.
    public static let empty = AppCatalog(sports: .empty, diceLines: [])
}

/// The art files the API serves over the ones the app bundles (the catalog's `art`): each at a
/// path of the art tree (`avatar/…`, `coaches/…`, `scenes/…`), downloaded from `baseURL` under
/// its SHA-256. A generation is used only once every one of its files is on the phone.
public struct ArtManifest: Hashable, Sendable {
    public struct File: Hashable, Sendable {
        public let path: String
        /// Lowercase hex; with the path's extension, the file's name under `baseURL`.
        public let sha256: String
        public let size: Int
        /// The lowest rig version that draws it.
        public let rigVersion: Int

        public init(path: String, sha256: String, size: Int, rigVersion: Int) {
            (self.path, self.sha256, self.size, self.rigVersion) = (path, sha256, size, rigVersion)
        }

        /// Its name in the bucket: the SHA-256 and the path's extension.
        public var name: String { "\(sha256).\(path.split(separator: ".").last ?? "")" }
    }

    /// The newest change's number; 0 for nothing put.
    public let generation: Int
    public let baseURL: URL?
    public let files: [File]

    public init(generation: Int, baseURL: URL?, files: [File]) {
        (self.generation, self.baseURL, self.files) = (generation, baseURL, files)
    }

    /// Nothing put: the bundled art alone.
    public static let none = ArtManifest(generation: 0, baseURL: nil, files: [])
}

/// A scene as the catalog lists it (its `scenes` section).
public struct CatalogScene: Hashable, Sendable {
    /// Its colours, `#RRGGBB`.
    public struct Colors: Hashable, Sendable {
        public let signature: String
        public let onSignature: String
        public let wash: String
        public let text: String
        public let floor: String

        public init(signature: String, onSignature: String, wash: String, text: String, floor: String) {
            (self.signature, self.onSignature, self.wash, self.text, self.floor) = (
                signature, onSignature, wash, text, floor
            )
        }
    }

    public let id: SceneID
    public let names: CatalogNames
    public let colors: Colors

    public init(id: SceneID, names: CatalogNames, colors: Colors) {
        (self.id, self.names, self.colors) = (id, names, colors)
    }
}
