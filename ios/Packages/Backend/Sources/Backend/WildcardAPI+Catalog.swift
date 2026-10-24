import APIContract
import Foundation

// The lists the server owns, such as the sports list, which the app reads signed out.
extension WildcardAPI {
    /// `GET /public/catalog`, which needs no sign-in: the catalog and its `ETag`, or nil while
    /// it is still the one named `known`.
    func catalogWire(ifNoneMatch known: String?) async throws(APIError) -> (
        catalog: Components.Schemas.Catalog, etag: String?
    )? {
        try await call {
            switch try await client.getCatalog(headers: .init(ifNoneMatch: known)) {
            case .ok(let answer): (try answer.body.json, answer.headers.eTag)
            case .notModified: nil
            default: throw APIError.unreadableResponse
            }
        }
    }
}
