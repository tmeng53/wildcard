#if os(iOS)
import Contracts
import CoreLocation
import LocationDomain
import MapKit

/// The phone's location through Core Location, approximate only: the app's Info.plist sets
/// `NSLocationDefaultAccuracyReduced`, so iOS never offers precise location, and it asks only
/// while the app is in use; and the city it is in, through MapKit's reverse geocoding. The only
/// code that knows Core Location and MapKit's geocoding.
@MainActor
public final class CoreLocationReader: NSObject, LocationReader {
    private let manager = CLLocationManager()
    /// The language cities are named in: the app's, read each time, as it can change in the app.
    private let locale: @MainActor () -> Locale
    /// Callers waiting for the member's answer on the system's prompt.
    private var answerWaiters: [CheckedContinuation<Void, Never>] = []
    /// Callers waiting for the one location `requestLocation` reads.
    private var placeWaiters: [CheckedContinuation<Coordinates?, Never>] = []

    public init(locale: @escaping @MainActor () -> Locale) {
        self.locale = locale
        super.init()
        manager.desiredAccuracy = kCLLocationAccuracyReduced
        manager.delegate = self
    }

    public func access() async -> LocationAccess {
        Self.access(of: manager.authorizationStatus)
    }

    public func ask() async -> LocationAccess {
        if manager.authorizationStatus == .notDetermined {
            await withCheckedContinuation { continuation in
                answerWaiters.append(continuation)
                if answerWaiters.count == 1 { manager.requestWhenInUseAuthorization() }
            }
        }
        return Self.access(of: manager.authorizationStatus)
    }

    public func current() async -> Coordinates? {
        guard Self.access(of: manager.authorizationStatus) == .allowed else { return nil }
        return await withCheckedContinuation { continuation in
            placeWaiters.append(continuation)
            if placeWaiters.count == 1 { manager.requestLocation() }
        }
    }

    /// Where the phone is now, as near as the member lets it be, for 添加位置's nearby places
    /// (Tracy, 2026-11-12): with location allowed, iOS asks once a session for precise location
    /// (`NearbyPlaces` in the Info.plist's `NSLocationTemporaryUsageDescriptionDictionary`); said
    /// no, the approximate one. Nil when location isn't allowed: the page then only searches.
    /// Never asks for location itself, and the phone's position never leaves the phone.
    public func nearHere() async -> Coordinates? {
        guard Self.access(of: manager.authorizationStatus) == .allowed else { return nil }
        if manager.accuracyAuthorization == .reducedAccuracy {
            // The completion form, so the manager never leaves the main actor.
            await withCheckedContinuation { (answered: CheckedContinuation<Void, Never>) in
                manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "NearbyPlaces") { _ in
                    answered.resume()
                }
            }
        }
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        defer { manager.desiredAccuracy = kCLLocationAccuracyReduced }
        return await current()
    }

    public func city(at coordinates: Coordinates) async -> CityName? {
        let place = CLLocation(latitude: coordinates.latitude, longitude: coordinates.longitude)
        guard let request = MKReverseGeocodingRequest(location: place) else { return nil }
        request.preferredLocale = locale()
        // No network, or Apple's limit on look-ups: no city this time, asked again on a later open.
        guard let item = try? await request.mapItems.first,
            let name = item.addressRepresentations?.cityName
        else { return nil }
        return CityName(name)
    }

    private static func access(of status: CLAuthorizationStatus) -> LocationAccess {
        switch status {
        case .notDetermined: .notAsked
        case .authorizedWhenInUse, .authorizedAlways: .allowed
        case .denied, .restricted: .refused
        @unknown default: .refused
        }
    }

    private func answered() {
        // Also called as the delegate is set, before anyone was asked.
        guard manager.authorizationStatus != .notDetermined else { return }
        let waiters = answerWaiters
        answerWaiters = []
        for waiter in waiters { waiter.resume() }
    }

    private func located(_ place: Coordinates?) {
        let waiters = placeWaiters
        placeWaiters = []
        for waiter in waiters { waiter.resume(returning: place) }
    }
}

extension CoreLocationReader: CLLocationManagerDelegate {
    nonisolated public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.answered() }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let place = locations.last.map {
            Coordinates(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
        }
        Task { @MainActor in self.located(place) }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        Task { @MainActor in self.located(nil) }
    }
}
#endif
