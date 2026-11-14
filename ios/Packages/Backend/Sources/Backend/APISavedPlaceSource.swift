import APIContract
import Contracts
import Foundation
import PlacesDomain

/// 收藏 over our API (`GET` and `PUT /me/saved-places`, `DELETE /me/saved-places/{placeKey}`):
/// the places the member saved, each with their note, which only they see.
public struct APISavedPlaceSource: SavedPlaceSource {
    private let api: WildcardAPI

    public init(api: WildcardAPI) {
        self.api = api
    }

    public func list() async throws(SavedPlacesError) -> [SavedPlace] {
        do throws(APIError) {
            let wire = try await api.call { try await api.client.listMySavedPlaces().ok.body.json }
            // One this build can't read is left out, never the whole list.
            return wire.places.compactMap { try? SavedPlace($0) }
        } catch {
            throw SavedPlacesError(error)
        }
    }

    public func save(_ place: Place, note: SavedPlaceNote?) async throws(SavedPlacesError) -> SavedPlace {
        do throws(APIError) {
            let wire = try await api.call {
                try await api.client.saveMyPlace(
                    body: .json(.init(version: ._1, place: place.wire, note: note?.text))
                ).ok.body.json
            }
            return try api.read { () throws(ContractsError) in try SavedPlace(wire.saved) }
        } catch {
            throw SavedPlacesError(error)
        }
    }

    public func remove(_ key: PlaceKey) async throws(SavedPlacesError) {
        do throws(APIError) {
            _ = try await api.call {
                try await api.client.removeMySavedPlace(path: .init(placeKey: key.rawValue)).noContent
            }
        } catch {
            throw SavedPlacesError(error)
        }
    }
}

extension SavedPlace {
    init(_ wire: Components.Schemas.SavedPlace) throws(ContractsError) {
        guard let key = PlaceKey(rawValue: wire.key) else { throw .invalidID(wire.key) }
        self.init(
            key: key, place: try Place(wire.place),
            note: try wire.note.map { text throws(ContractsError) in
                try SavedPlaceNote(text)
            }, savedAt: Timestamp(wire.savedAt))
    }
}

extension SavedPlacesError {
    /// What a failed API call means for 收藏.
    init(_ error: APIError) {
        self =
            switch error {
            case .account(.signedOut), .account(.credentialRejected), .account(.canceled): .signedOut
            case .refused(.savedPlacesFull): .full
            default: .unavailable
            }
    }
}
