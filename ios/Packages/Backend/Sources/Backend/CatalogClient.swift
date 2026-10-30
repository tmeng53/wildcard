import APIContract
import Contracts
import Foundation

/// The catalog the API serves (`GET /public/catalog`): what the app shows that lives in the
/// database, such as every sport and the 请假条 dice lines, so it changes without an app release.
/// The last one read is kept on the device, as the API sent it, and the one this build ships with
/// (`catalog.json`, `pnpm --dir api catalog-snapshot`) stands in until the first read. Nothing in
/// it is the member's, so it stays on sign-out.
public actor CatalogClient {
    private let api: WildcardAPI
    private let saved: URL

    /// - Parameters:
    ///   - directory: where the copy is kept, such as Application Support.
    public init(api: WildcardAPI, directory: URL) {
        self.api = api
        saved = directory.appending(path: "catalog.json")
    }

    /// The catalog to show before the API answers: the last one read, else the one this build
    /// ships with.
    public nonisolated func kept() -> AppCatalog {
        Self.read(saved).map { AppCatalog($0.catalog, otherwise: Self.bundled) } ?? Self.bundled
    }

    /// Reads the API's catalog and keeps it; the catalog, or nil when it is unchanged since the
    /// last read or the API can't be reached (the kept one stays).
    public func refresh() async -> AppCatalog? {
        let copy = Self.read(saved)
        guard let read = try? await api.catalogWire(ifNoneMatch: copy?.etag) else { return nil }
        let fresh = SavedCatalog(version: 1, etag: read.etag, catalog: read.catalog)
        if let data = try? JSONEncoder().encode(fresh) { try? DeviceJSON.write(data, to: saved) }
        let catalog = AppCatalog(read.catalog, otherwise: Self.bundled)
        return catalog == (copy.map { AppCatalog($0.catalog, otherwise: Self.bundled) } ?? Self.bundled) ? nil : catalog
    }

    /// The catalog this build ships with.
    public static let bundled: AppCatalog = {
        guard let url = Bundle.module.url(forResource: "catalog", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let catalog = try? JSONDecoder().decode(Components.Schemas.Catalog.self, from: data)
        else {
            // The build's own file; a test reads it.
            return .empty
        }
        return AppCatalog(catalog, otherwise: .empty)
    }()

    /// The copy kept at `url`; nil when there is none, or it is in a shape this build can't read,
    /// so the bundled one stands in.
    private static func read(_ url: URL) -> SavedCatalog? {
        guard let data = try? Data(contentsOf: url),
            let copy = try? JSONDecoder().decode(SavedCatalog.self, from: data),
            copy.version == 1
        else { return nil }
        return copy
    }
}

/// The catalog as the API sent it, with its `ETag`. Stored JSON, so it carries a `version`.
private struct SavedCatalog: Codable {
    let version: Int
    let etag: String?
    let catalog: Components.Schemas.Catalog
}
