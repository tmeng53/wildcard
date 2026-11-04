import Foundation

/// Everything the catalog (`GET /public/catalog`) holds that this build reads: data the app shows
/// that lives in the database, so it changes without an app release.
public struct AppCatalog: Hashable, Sendable {
    /// Every sport the pickers show.
    public let sports: SportCatalog
    /// The ready-made 请假条 lines rolled when the AI can't write.
    public let diceLines: [CatalogNames]
    /// The global switches limited stores follow, by id.
    public let switches: [String: CatalogSwitch]
    /// The art files put over the ones this build bundles.
    public let art: ArtManifest

    public init(
        sports: SportCatalog, diceLines: [CatalogNames], switches: [String: CatalogSwitch] = [:],
        art: ArtManifest = .none
    ) {
        (self.sports, self.diceLines, self.switches, self.art) = (sports, diceLines, switches, art)
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
