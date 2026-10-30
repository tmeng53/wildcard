import APIContract
import Contracts
import Foundation

/// The catalog the API serves (`GET /public/catalog`): lists the app shows that live in the
/// database, such as every sport, so they change without an app release. The last one read is
/// kept on the device, as the API sent it, and the one this build ships with (`catalog.json`,
/// `pnpm --dir api catalog-snapshot`) stands in until the first read. Nothing in it is the
/// member's, so it stays on sign-out.
public actor CatalogClient {
    private let api: WildcardAPI
    private let saved: URL

    /// - Parameters:
    ///   - directory: where the copy is kept, such as Application Support.
    public init(api: WildcardAPI, directory: URL) {
        self.api = api
        saved = directory.appending(path: "catalog.json")
    }

    /// The sports to show before the API answers: the last list read, else the one this build
    /// ships with.
    public nonisolated func keptSports() -> SportCatalog {
        guard let data = try? Data(contentsOf: saved),
            let copy = try? JSONDecoder().decode(SavedCatalog.self, from: data),
            copy.version == 1
        else { return Self.bundledSports }
        return SportCatalog(copy.catalog.sports)
    }

    /// Reads the API's catalog and keeps it; its sports, or nil when they are unchanged since the
    /// last read or the API can't be reached (the kept list stays).
    public func refreshSports() async -> SportCatalog? {
        let kept = (try? Data(contentsOf: saved)).flatMap { try? JSONDecoder().decode(SavedCatalog.self, from: $0) }
        guard let read = try? await api.catalogWire(ifNoneMatch: kept?.etag) else { return nil }
        let copy = SavedCatalog(version: 1, etag: read.etag, catalog: read.catalog)
        if let data = try? JSONEncoder().encode(copy) { try? DeviceJSON.write(data, to: saved) }
        let sports = SportCatalog(read.catalog.sports)
        return sports == keptSports(of: kept) ? nil : sports
    }

    /// The sports this build ships with.
    public static let bundledSports: SportCatalog = {
        guard let url = Bundle.module.url(forResource: "catalog", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let catalog = try? JSONDecoder().decode(Components.Schemas.Catalog.self, from: data)
        else {
            // The build's own file; a test reads it.
            return .empty
        }
        return SportCatalog(catalog.sports)
    }()

    private func keptSports(of copy: SavedCatalog?) -> SportCatalog {
        copy.map { SportCatalog($0.catalog.sports) } ?? Self.bundledSports
    }
}

/// The catalog as the API sent it, with its `ETag`. Stored JSON, so it carries a `version`.
private struct SavedCatalog: Codable {
    let version: Int
    let etag: String?
    let catalog: Components.Schemas.Catalog
}
