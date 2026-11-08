#if os(iOS)
import CoreLocation
import LocationDomain

/// The phone's location through Core Location, approximate only: the app's Info.plist sets
/// `NSLocationDefaultAccuracyReduced`, so iOS never offers precise location, and it asks only
/// while the app is in use. The only code that knows Core Location.
@MainActor
public final class CoreLocationReader: NSObject, LocationReader {
    private let manager = CLLocationManager()
    /// Callers waiting for the member's answer on the system's prompt.
    private var answerWaiters: [CheckedContinuation<Void, Never>] = []
    /// Callers waiting for the one location `requestLocation` reads.
    private var placeWaiters: [CheckedContinuation<Coordinates?, Never>] = []

    override public init() {
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
