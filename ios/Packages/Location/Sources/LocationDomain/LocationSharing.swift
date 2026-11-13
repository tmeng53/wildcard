import Contracts
import Foundation
import Observation

/// Roughly where the phone is: iOS's approximate location, a few kilometres wide.
public struct Coordinates: Hashable, Sendable, Codable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// The 0.1° cell the server keeps (about 11 km), so a move within it isn't sent again.
    public var cell: Coordinates {
        Coordinates(latitude: (latitude * 10).rounded() / 10, longitude: (longitude * 10).rounded() / 10)
    }
}

/// Whether the member lets the app read the phone's location.
public enum LocationAccess: Sendable, Equatable {
    /// Not asked yet: asking shows the system's prompt.
    case notAsked
    case allowed
    /// Refused, or not allowed on this phone: only iOS Settings can change it.
    case refused
}

/// Why the server didn't take the place.
public enum LocationError: Error, Equatable, Sendable {
    /// The session is over; whoever signs in next sends their own.
    case signedOut
    /// No network or no server: tried again on the next open.
    case unavailable
}

/// The phone's location, read through the system.
public protocol LocationReader: Sendable {
    func access() async -> LocationAccess
    /// Shows the system's prompt when not asked yet, and answers what the member chose.
    func ask() async -> LocationAccess
    /// Where the phone roughly is now, or nil when it can't tell.
    func current() async -> Coordinates?
    /// The city `coordinates` are in, in the app's language, or nil when it can't tell.
    func city(at coordinates: Coordinates) async -> CityName?
}

/// Where the server keeps the member's place, for their coach's weather.
public protocol LocationRegistry: Sendable {
    /// Keeps the place with its city; without one, the city kept before is forgotten too.
    func save(_ coordinates: Coordinates, city: CityName?) async throws(LocationError)
    func forget() async throws(LocationError)
}

/// What this phone sent last for the member signed in, kept on the phone.
public struct SentPlace: Hashable, Sendable, Codable {
    public var version = 1
    public let cell: Coordinates
    /// The city sent with it; nil when iOS couldn't name one, or sent by a build before cities.
    public let city: CityName?
    public let sentAt: Date

    public init(cell: Coordinates, city: CityName?, sentAt: Date) {
        self.cell = cell
        self.city = city
        self.sentAt = sentAt
    }
}

/// Where `SentPlace` is kept.
public protocol SentPlaceStore: Sendable {
    func load() -> SentPlace?
    func save(_ place: SentPlace?)
}

/// The member's location for the coach's weather, one for the app: sign-up's 打开大概位置 and
/// 设置 › 位置 ask with it, and the app syncs it each time it comes to the front. It sends a place,
/// with the city iOS names there, only when it moved to another cell, a day passed or the city
/// sent before wasn't known, and asks the server to forget it once the member stops allowing
/// location.
@MainActor @Observable
public final class LocationSharing {
    public private(set) var access: LocationAccess = .notAsked
    /// Asking is under way, so the button waits.
    public private(set) var isAsking = false

    @ObservationIgnored private let reader: any LocationReader
    @ObservationIgnored private let sent: any SentPlaceStore
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var registry: (any LocationRegistry)?
    /// The server was told to forget the place since this member signed in on this launch. A
    /// place this phone no longer remembers sending (signed out, reinstalled) may still be kept
    /// there, so a member who doesn't allow location is forgotten once each launch.
    @ObservationIgnored private var forgotten = false

    /// A place sent longer ago than this is sent again, in case the server lost it.
    static let resendAfter: TimeInterval = 24 * 60 * 60

    public init(reader: any LocationReader, sent: any SentPlaceStore, now: @escaping () -> Date = Date.init) {
        self.reader = reader
        self.sent = sent
        self.now = now
    }

    /// Someone signed in: their place goes to their account from now on.
    public func signedIn(_ registry: any LocationRegistry) async {
        self.registry = registry
        forgotten = false
        await refresh()
    }

    /// Signed out: the next member sends their own, so what this phone sent is forgotten here.
    public func signedOut() {
        registry = nil
        forgotten = false
        sent.save(nil)
    }

    /// 允许: the system's prompt when not asked yet, then sends the place if allowed.
    public func ask() async {
        guard !isAsking else { return }
        isAsking = true
        access = await reader.ask()
        isAsking = false
        await sync()
    }

    /// Reads whether location is allowed, and sends or forgets the place to match.
    public func refresh() async {
        access = await reader.access()
        await sync()
    }

    private func sync() async {
        guard let registry else { return }
        do throws(LocationError) {
            switch access {
            case .allowed:
                guard let here = await reader.current() else { return }
                let cell = here.cell
                let time = now()
                let last = sent.load()
                let fresh =
                    last.map { $0.cell == cell && time.timeIntervalSince($0.sentAt) < Self.resendAfter }
                    ?? false
                // The city is looked up only when something may be sent, and again while it
                // wasn't known, so the coach learns it as soon as iOS can name it.
                if fresh, last?.city != nil { return }
                let city = await reader.city(at: here)
                if fresh, city == nil { return }
                try await registry.save(cell, city: city)
                sent.save(SentPlace(cell: cell, city: city, sentAt: time))
                forgotten = false
            case .refused, .notAsked:
                guard sent.load() != nil || !forgotten else { return }
                try await registry.forget()
                sent.save(nil)
                forgotten = true
            }
        } catch {
            // Tried again the next time the app comes to the front.
        }
    }
}
