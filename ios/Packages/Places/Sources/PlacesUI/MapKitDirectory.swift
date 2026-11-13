#if os(iOS)
import Contracts
import MapKit
import PlacesDomain

/// Apple Maps through MapKit, on the phone: a place's address, phone and website by its Maps id.
/// A place without one, or one Maps can't find now, has no facts; its card shows without them.
public struct MapKitDirectory: PlaceDirectory {
    public init() {}

    public func facts(for place: Place) async -> PlaceFacts? {
        guard let id = place.appleID.flatMap(MKMapItem.Identifier.init(rawValue:)) else { return nil }
        let request = MKMapItemRequest(mapItemIdentifier: id)
        // Through the completion handler, as `RouteSnapshot` does, so nothing MapKit hands back
        // crosses an actor.
        return await withCheckedContinuation { continuation in
            request.getMapItem { item, _ in
                continuation.resume(
                    returning: item.map {
                        PlaceFacts(address: $0.address?.shortAddress, phone: $0.phoneNumber, website: $0.url)
                    })
            }
        }
    }
}
#endif
