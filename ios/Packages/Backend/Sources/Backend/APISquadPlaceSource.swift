import APIContract
import CheckInDomain
import Contracts
import Foundation

/// The places a squad's members added themselves (自建地点) over our API: `GET
/// /squads/{squadId}/custom-places` lists them for the place picker, and `PUT
/// …/custom-places/{placeId}` adds one under the id the app made, so trying again adds it once.
public struct APISquadPlaceSource: SquadPlaceSource {
    private let api: WildcardAPI

    public init(api: WildcardAPI) {
        self.api = api
    }

    public func places(in squad: SquadID) async throws(SquadPlacesError) -> [SquadPlace] {
        do throws(APIError) {
            let wire = try await api.call {
                try await api.client.listSquadCustomPlaces(path: .init(squadId: squad.description)).ok.body.json
            }
            // One this build can't read is left out, never the whole list.
            return wire.places.compactMap { try? SquadPlace($0) }
        } catch {
            throw SquadPlacesError(error)
        }
    }

    public func add(_ new: NewSquadPlace, id: UUID, to squad: SquadID) async throws(SquadPlacesError) -> SquadPlace {
        guard let kind = Components.Schemas.SquadPlaceChange.KindPayload(rawValue: new.kind.rawValue) else {
            throw .unavailable
        }
        do throws(APIError) {
            let wire = try await api.call {
                switch try await api.client.addSquadCustomPlace(
                    path: .init(squadId: squad.description, placeId: id.uuidString.lowercased()),
                    body: .json(
                        .init(
                            version: ._1, name: new.name, kind: kind, latitude: new.latitude, longitude: new.longitude))
                )
                {
                case .created(let added): return try added.body.json.place
                case .ok(let same): return try same.body.json.place
                default: throw APIError.unreadableResponse
                }
            }
            return try api.read { () throws(ContractsError) in try SquadPlace(wire) }
        } catch {
            throw SquadPlacesError(error)
        }
    }
}

extension SquadPlace {
    init(_ wire: Components.Schemas.SquadPlace) throws(ContractsError) {
        guard let id = UUID(uuidString: wire.id), let kind = SquadPlaceKind(rawValue: wire.kind.rawValue) else {
            throw .invalidID(wire.id)
        }
        try self.init(
            id: id, name: wire.name, kind: kind, latitude: wire.latitude, longitude: wire.longitude,
            addedBy: wire.addedBy.flatMap(UUID.init(uuidString:)).map(MemberID.init))
    }
}

extension SquadPlacesError {
    /// What a failed API call means for the squad's places.
    init(_ error: APIError) {
        self =
            switch error {
            case .account(.signedOut), .account(.credentialRejected), .account(.canceled): .signedOut
            case .refused(.squadNotJoined): .notInSquad
            default: .unavailable
            }
    }
}
