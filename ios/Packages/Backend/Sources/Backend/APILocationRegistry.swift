import APIContract
import Foundation
import LocationDomain

/// Where the member roughly is, over `PUT` and `DELETE /me/location`: behind `LocationSharing`,
/// for the coach's weather.
public struct APILocationRegistry: LocationRegistry {
    private let api: WildcardAPI

    public init(api: WildcardAPI) {
        self.api = api
    }

    public func save(_ coordinates: Coordinates) async throws(LocationError) {
        do {
            _ = try await api.call {
                try await api.client.saveMyLocation(
                    body: .json(.init(version: ._1, latitude: coordinates.latitude, longitude: coordinates.longitude))
                ).ok
            }
        } catch {
            throw Self.reason(error)
        }
    }

    public func forget() async throws(LocationError) {
        do {
            _ = try await api.call { try await api.client.forgetMyLocation().noContent }
        } catch {
            throw Self.reason(error)
        }
    }

    /// Only a session that is over means something here; anything else is tried on the next open.
    private static func reason(_ error: APIError) -> LocationError {
        error == .account(.signedOut) ? .signedOut : .unavailable
    }
}
