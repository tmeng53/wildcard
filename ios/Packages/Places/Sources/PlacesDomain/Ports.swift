import Contracts
import Foundation

/// Where a place's squad numbers come from: the API, for the signed-in member. `Backend` has the
/// adapter.
public protocol PlaceSource: Sendable {
    /// What the squad did at the place; nil when no post in the squad's 动态 was tagged there.
    func detail(of place: PlaceKey, in squad: SquadID) async throws(PlacesError) -> PlaceDetail?
    /// The squad's members' characters, for the posts' authors. A member who hasn't made one
    /// yet is missing.
    func characters(in squad: SquadID) async throws(PlacesError) -> [MemberID: MemberCharacter]
    /// A post's photo, as JPEG. Nil when it can't be had now; its tile shows its colour.
    func photo(_ ref: PhotoRef) async -> Data?
}

/// What Apple Maps says of a place: its address, phone and website. `PlacesUI` reads it with
/// MapKit on the phone.
public protocol PlaceDirectory: Sendable {
    /// Nil when Maps can't be reached or doesn't know the place.
    func facts(for place: Place) async -> PlaceFacts?
}
