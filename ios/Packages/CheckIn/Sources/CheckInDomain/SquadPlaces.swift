import Contracts
import Foundation

/// 吃的, 健身 or 户外: the kind a member gives a place they add for the squad (自建地点), which
/// picks its icon. A post tags the place with the Apple Maps category that wears the same icon,
/// so every place's tag, pin and row reads it as `PlaceKind` reads any other.
public enum SquadPlaceKind: String, CaseIterable, Sendable {
    case food
    case gym
    case outdoor

    /// The category a tagged place keeps for it.
    public var category: String {
        switch self {
        case .food: "restaurant"
        case .gym: "fitnessCenter"
        case .outdoor: "park"
        }
    }

    /// The SF Symbol its tag, pin and picker show.
    public var symbol: String { PlaceKind(category: category).symbol }
}

/// A place one of the squad's members added because Apple Maps doesn't list it (公司食堂, 小区健身房;
/// Tracy, 2026-11-12): the whole squad sees it and may tag their posts with it. Never changed
/// once added.
public struct SquadPlace: Identifiable, Hashable, Sendable {
    public let id: UUID
    /// The place as a post tags it: its name, coordinates and `squadPlaceID`.
    public let place: Place
    public let kind: SquadPlaceKind
    /// Who added it; nil once they deleted their account.
    public let addedBy: MemberID?

    /// Fails for a name the API wouldn't take or coordinates off the globe.
    public init(
        id: UUID, name: String, kind: SquadPlaceKind, latitude: Double, longitude: Double, addedBy: MemberID?
    ) throws(ContractsError) {
        self.id = id
        place = try Place(
            name: name, squadPlaceID: id, category: kind.category, latitude: latitude, longitude: longitude)
        self.kind = kind
        self.addedBy = addedBy
    }

    /// Whether its name has what the member typed in it, ignoring case and width, as the picker
    /// lists the squad's places beside what Apple Maps suggests.
    public func matches(_ typed: String) -> Bool {
        let typed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return true }
        return place.name.range(of: typed, options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive])
            != nil
    }
}

/// A place a member is adding for the squad: its name, kind and where its pin stands. Fails for
/// a name the API wouldn't take or coordinates off the globe, so 添加 stays off until it holds.
/// The pin's coordinates are rounded to 6 decimals (about 10 cm), so the same place sent again
/// reads back the same from the database and a retry adds it once.
public struct NewSquadPlace: Hashable, Sendable {
    public let name: String
    public let kind: SquadPlaceKind
    public let latitude: Double
    public let longitude: Double

    public init(name: String, kind: SquadPlaceKind, latitude: Double, longitude: Double) throws(ContractsError) {
        let checked = try Place(name: name, latitude: latitude, longitude: longitude)
        (self.name, self.kind) = (checked.name, kind)
        (self.latitude, self.longitude) = (Self.rounded(latitude), Self.rounded(longitude))
    }

    private static func rounded(_ degrees: Double) -> Double {
        (degrees * 1_000_000).rounded() / 1_000_000
    }
}

/// Why the squad's places couldn't be read or a place couldn't be added.
public enum SquadPlacesError: Error, Equatable, Sendable {
    /// Not signed in any more.
    case signedOut
    /// Not in the squad any more.
    case notInSquad
    /// The server couldn't be reached or said no; nothing was added, and trying again is safe.
    case unavailable
}

/// Where a squad's own places come from and go to: the API, for the signed-in member. `Backend`
/// has the adapter; the sample squad keeps them in memory.
public protocol SquadPlaceSource: Sendable {
    /// The places the squad's members added, the earliest first.
    func places(in squad: SquadID) async throws(SquadPlacesError) -> [SquadPlace]
    /// Adds a place for the squad under `id`, which the caller made, so trying again adds it once.
    func add(_ new: NewSquadPlace, id: UUID, to squad: SquadID) async throws(SquadPlacesError) -> SquadPlace
}

/// The id 添加 sends for a new place: the same while the member tries the same place again, so a
/// retry after a lost answer adds it once, and a fresh one once they change the name, kind or pin,
/// since the API refuses other contents under an id it already holds.
public struct SquadPlaceAttempt: Sendable {
    private var sent: (draft: NewSquadPlace, id: UUID)?

    public init() {}

    public mutating func id(for draft: NewSquadPlace, making newID: () -> UUID) -> UUID {
        if let sent, sent.draft == draft { return sent.id }
        let id = newID()
        sent = (draft, id)
        return id
    }
}
