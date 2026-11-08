import LocationDomain

/// A phone that hasn't been asked yet and allows approximate location when asked, in New York, for
/// the sample squad, previews and UI tests: the simulator's own prompt can't be answered there.
public actor SampleLocationReader: LocationReader {
    private var state: LocationAccess

    public init(access: LocationAccess = .notAsked) {
        state = access
    }

    public func access() async -> LocationAccess { state }

    public func ask() async -> LocationAccess {
        if state == .notAsked { state = .allowed }
        return state
    }

    public func current() async -> Coordinates? {
        state == .allowed ? Coordinates(latitude: 40.7, longitude: -74) : nil
    }
}

extension LocationSharing {
    /// Location on the sample squad: `SampleLocationReader`, remembering what it sent only while
    /// the app runs.
    public static func sample(access: LocationAccess = .notAsked) -> LocationSharing {
        LocationSharing(reader: SampleLocationReader(access: access), sent: SampleSentPlace())
    }
}

/// What the sample sent, kept in memory only.
private final class SampleSentPlace: SentPlaceStore, @unchecked Sendable {  // Main actor only.
    private var place: SentPlace?
    func load() -> SentPlace? { place }
    func save(_ place: SentPlace?) { self.place = place }
}
