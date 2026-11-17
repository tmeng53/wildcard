import CheckInDomain
import Contracts
import DesignSystemUI
import Foundation

#if canImport(SwiftUI)
import SwiftUI

/// The squad's own places (自建地点) for the place picker: where they are read and added, the
/// squad they belong to, and the names of who added them. The app passes it in, since the squad
/// and its members live above the compose page.
public struct SquadPlaceBook: Sendable {
    let source: (any SquadPlaceSource)?
    let squad: SquadID?
    let name: @MainActor @Sendable (MemberID) -> String?

    public init(
        source: any SquadPlaceSource, squad: SquadID?, name: @escaping @MainActor @Sendable (MemberID) -> String?
    ) {
        (self.source, self.squad, self.name) = (source, squad, name)
    }

    private init() {
        (source, squad, name) = (nil, nil, { _ in nil })
    }

    /// No squad's places (the sign-up preview, the style guide): the picker shows Apple Maps' alone.
    public static let unwired = SquadPlaceBook()

    /// The source and squad, when a squad's places can be read and added.
    var wired: (source: any SquadPlaceSource, squad: SquadID)? {
        guard let source, let squad else { return nil }
        return (source, squad)
    }
}

extension EnvironmentValues {
    @Entry public var squadPlaces = SquadPlaceBook.unwired
}
#endif

/// A squad's places kept in memory, for the sample squad and UI tests: two teammates added the
/// office canteen and the building's gym near the sample's places, the first time it is read.
public actor InMemorySquadPlaceSource: SquadPlaceSource {
    private var added: [SquadPlace]?
    private let teammates: @Sendable () async -> [MemberID]

    /// `teammates` names who added the sample's two places, the first two it gives.
    public init(teammates: @escaping @Sendable () async -> [MemberID]) {
        self.teammates = teammates
    }

    public func places(in squad: SquadID) async throws(SquadPlacesError) -> [SquadPlace] {
        if let added { return added }
        let mates = await teammates()
        let sample = [
            try? SquadPlace(
                id: UUID(), name: String(copy: "公司食堂", bundle: .module), kind: .food, latitude: 40.7466,
                longitude: -73.9895, addedBy: mates.first),
            try? SquadPlace(
                id: UUID(), name: String(copy: "小区健身房", bundle: .module), kind: .gym, latitude: 40.7398,
                longitude: -73.9932, addedBy: mates.dropFirst().first),
        ].compactMap(\.self)
        added = sample
        return sample
    }

    public func add(_ new: NewSquadPlace, id: UUID, to squad: SquadID) async throws(SquadPlacesError) -> SquadPlace {
        let known = try await places(in: squad)
        if let same = known.first(where: { $0.id == id }) { return same }
        guard
            let place = try? SquadPlace(
                id: id, name: new.name, kind: new.kind, latitude: new.latitude, longitude: new.longitude, addedBy: nil)
        else { throw .unavailable }
        added = known + [place]
        return place
    }
}
