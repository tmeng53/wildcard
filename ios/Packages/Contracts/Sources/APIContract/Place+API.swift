import Contracts
import Foundation

// A place's page as the API sends it (`GET /squads/{squadId}/places/{key}`): the parts that are
// `Contracts` types, which the place page's adapter reads.

extension Place {
    /// The place as the newest post there tagged it.
    public init(_ wire: Components.Schemas.PlaceDetail.PlacePayload) throws(ContractsError) {
        try self.init(
            name: wire.name, appleID: wire.appleId, category: wire.category, latitude: wire.latitude,
            longitude: wire.longitude)
    }
}

extension Place {
    /// A place the member saved (收藏), as they saved it.
    public init(_ wire: Components.Schemas.Place) throws(ContractsError) {
        try self.init(
            name: wire.name, appleID: wire.appleId, category: wire.category, latitude: wire.latitude,
            longitude: wire.longitude)
    }
}

extension Place {
    /// A place on 小队地图, as the newest post there tagged it.
    public init(_ wire: Components.Schemas.PlaceSummary.PlacePayload) throws(ContractsError) {
        try self.init(
            name: wire.name, appleID: wire.appleId, category: wire.category, latitude: wire.latitude,
            longitude: wire.longitude)
    }
}

extension Activity {
    /// A sport the squad trained at a place on 小队地图.
    public init(_ wire: Components.Schemas.PlaceSummary.SportsPayloadPayload) throws(ContractsError) {
        try self.init(sport: wire.sport, customSport: wire.customSport)
    }

    /// A sport the squad trained at a place.
    public init(_ wire: Components.Schemas.PlaceDetail.SportsPayloadPayload) throws(ContractsError) {
        try self.init(sport: wire.sport, customSport: wire.customSport)
    }

    /// A 训练's sport on one of a place's posts; nil for a meal.
    public init?(_ wire: Components.Schemas.PlaceVisit) throws(ContractsError) {
        guard let sport = wire.sport else { return nil }
        try self.init(sport: sport, customSport: wire.customSport)
    }
}

extension PhotoRef {
    /// A post's cover on a place's page, with its view URL.
    public init(_ wire: Components.Schemas.PhotoView) throws(ContractsError) {
        guard let url = URL(string: wire.url) else { throw .invalidPhotoURL(wire.url) }
        let size = try wire.size.map { size throws(ContractsError) in
            try PhotoSize(width: size.width, height: size.height)
        }
        try self.init(path: wire.path, size: size, viewURL: url)
    }
}
