#if os(iOS)
import CheckInDomain
import Contracts
import DesignSystemUI
import LocationUI
import MapKit

/// One place Apple Maps found, as a row and a pin show it.
struct FoundPlace: Identifiable, Hashable, Sendable {
    let place: Place
    let address: String?
    /// Metres from the phone, when the phone's place is known.
    let distance: Double?

    var id: String {
        place.squadPlaceID?.uuidString ?? place.appleID ?? "\(place.name)|\(place.latitude)|\(place.longitude)"
    }
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
    }
}

/// A suggestion Apple Maps makes for what the member is typing: a place, an address or a kind of
/// place ("餐厅"), as its search box makes them.
struct Suggestion: Identifiable {
    let title: String
    let subtitle: String?

    /// Its words, so a tap finds the same suggestion after the list changed under it.
    var id: String { "\(title)\n\(subtitle ?? "")" }
}

/// The places around the phone, then, as the member types, Apple Maps' suggestions near the phone
/// (its autocomplete, `MKLocalSearchCompleter`), and the places a suggestion or the keyboard's 搜索
/// finds (Tracy, 2026-11-14: search like Apple Maps). Every place, not only some kinds, in Apple's
/// own order. The phone's position is used only on the phone, to search near it; only the picked
/// place goes in the post.
@MainActor
@Observable
final class PlaceSearch {
    /// The places the list and the map show: nearby ones, or what a search found.
    private(set) var found: [FoundPlace] = []
    /// Apple Maps' suggestions for what is typed, which the list shows over the places while typing.
    private(set) var suggestions: [Suggestion] = []
    private(set) var isSuggesting = false
    private(set) var here: CLLocation?
    private var nearby: [FoundPlace] = []
    /// What the member typed, so the nearby list never replaces a search's results.
    private var typed = ""
    /// Counts what was typed, so a search that answers after the member typed on is dropped.
    private var asked = 0
    /// Whether Apple Maps is asked at all; off, the list holds only the squad's places and 新建, and
    /// 搜索 finds one fixed place named what was typed, as the UI tests need, since what Maps
    /// answers changes from run to run.
    var asksAppleMaps = true
    private let completer = MKLocalSearchCompleter()
    @ObservationIgnored private var completions: [MKLocalSearchCompletion] = []
    @ObservationIgnored private var listener: CompleterListener?

    /// How far around the phone the nearby list looks.
    private static let radius: CLLocationDistance = 1000
    /// The span suggestions and searches lean to, around the phone, as Apple Maps' does; places
    /// beyond it still come, after nearer ones.
    private static let reach: CLLocationDistance = 20_000

    init() {
        completer.resultTypes = [.pointOfInterest, .address, .query]
        let listener = CompleterListener { [weak self] in self?.suggested() }
        completer.delegate = listener
        self.listener = listener
    }

    func lookAround() async {
        guard asksAppleMaps else { return }
        let reader = CoreLocationReader(locale: { AppLanguage.current.locale })
        // The approximate place first, so suggestions lean near the phone while iOS asks for the
        // precise one.
        if let rough = await reader.current() {
            locate(CLLocation(latitude: rough.latitude, longitude: rough.longitude))
        }
        guard let near = await reader.nearHere() else { return }
        let location = CLLocation(latitude: near.latitude, longitude: near.longitude)
        locate(location)
        let request = MKLocalPointsOfInterestRequest(center: location.coordinate, radius: Self.radius)
        nearby = await places(MKLocalSearch(request: request), byDistance: true)
        if typed.isEmpty { found = nearby }
    }

    /// Asks Apple Maps for suggestions as the member types; nothing typed, the nearby places again.
    func type(_ query: String) {
        typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        asked += 1
        guard !typed.isEmpty else {
            completer.cancel()
            completions = []
            suggestions = []
            isSuggesting = false
            found = nearby
            return
        }
        isSuggesting = true
        completions = []
        suggestions = []
        guard asksAppleMaps else { return }
        completer.queryFragment = typed
    }

    /// The places a suggestion stands for: the one place it names, or every place a kind of place
    /// finds near the phone.
    func places(forSuggestion id: Suggestion.ID) async -> [FoundPlace] {
        guard let completion = completions.first(where: { Self.suggestion($0).id == id }) else { return [] }
        typed = completion.title
        return await show(MKLocalSearch.Request(completion: completion))
    }

    /// Every place what is typed finds, as the keyboard's 搜索 asks.
    func placesForTyped() async -> [FoundPlace] {
        guard !typed.isEmpty else { return [] }
        guard asksAppleMaps else { return showing(Self.fixed(named: typed)) }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = typed
        return await show(request)
    }

    private func show(_ request: MKLocalSearch.Request) async -> [FoundPlace] {
        request.resultTypes = [.pointOfInterest, .address]
        if let region { request.region = region }
        asked += 1
        let asking = asked
        let results = await places(MKLocalSearch(request: request), byDistance: false)
        // Dropped once the member typed on or asked again.
        guard asking == asked else { return [] }
        return showing(results)
    }

    /// What a search found becomes the list; nothing found, the suggestions stay.
    private func showing(_ results: [FoundPlace]) -> [FoundPlace] {
        guard !results.isEmpty else { return [] }
        isSuggesting = false
        found = results
        return results
    }

    /// The one place 搜索 finds without Apple Maps: named what was typed, near the sample squad.
    private static func fixed(named name: String) -> [FoundPlace] {
        guard let place = try? Place(name: name, appleID: nil, category: nil, latitude: 40.7484, longitude: -73.9857)
        else { return [] }
        return [FoundPlace(place: place, address: nil, distance: nil)]
    }

    private var region: MKCoordinateRegion? {
        here.map {
            MKCoordinateRegion(center: $0.coordinate, latitudinalMeters: Self.reach, longitudinalMeters: Self.reach)
        }
    }

    private func locate(_ location: CLLocation) {
        here = location
        if let region { completer.region = region }
    }

    private func suggested() {
        guard isSuggesting else { return }
        completions = completer.results
        var seen = Set<Suggestion.ID>()
        suggestions = Array(
            completions.map(Self.suggestion).filter { seen.insert($0.id).inserted }.prefix(Self.shownSuggestions))
    }

    /// How many of Apple Maps' suggestions the list shows while typing, so 新建 under them stays
    /// above the keyboard on the smallest phone (Tracy, 2026-11-22).
    private static let shownSuggestions = 3

    private static func suggestion(_ completion: MKLocalSearchCompletion) -> Suggestion {
        Suggestion(title: completion.title, subtitle: completion.subtitle.isEmpty ? nil : completion.subtitle)
    }

    /// Through the completion handler on the main queue, as `RouteSnapshot` does, so nothing
    /// MapKit hands back crosses an actor. A search's places keep Apple's order; the nearby ones
    /// go nearest first.
    private func places(_ search: MKLocalSearch, byDistance: Bool) async -> [FoundPlace] {
        let here = here
        return await withCheckedContinuation { continuation in
            search.start { response, _ in
                continuation.resume(returning: Self.found(in: response, near: here, byDistance: byDistance))
            }
        }
    }

    private static func found(
        in response: MKLocalSearch.Response?, near here: CLLocation?, byDistance: Bool
    ) -> [FoundPlace] {
        guard let response else { return [] }
        let places = response.mapItems.compactMap { item -> FoundPlace? in
            let location = item.location
            guard let name = item.name,
                let place = try? Place(
                    name: name, appleID: item.identifier?.rawValue,
                    category: item.pointOfInterestCategory.map { PlaceKind.category(fromMaps: $0.rawValue) },
                    latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
            else { return nil }
            return FoundPlace(
                place: place, address: item.address?.shortAddress, distance: here.map { $0.distance(from: location) })
        }
        guard byDistance else { return places }
        return places.sorted { ($0.distance ?? .infinity) < ($1.distance ?? .infinity) }
    }
}

/// Tells `PlaceSearch` that Apple Maps' suggestions changed. MapKit calls it on the main queue.
@MainActor
private final class CompleterListener: NSObject, MKLocalSearchCompleterDelegate {
    private let changed: @MainActor @Sendable () -> Void

    init(changed: @escaping @MainActor @Sendable () -> Void) {
        self.changed = changed
        super.init()
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let changed = changed
        Task { @MainActor in changed() }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        let changed = changed
        Task { @MainActor in changed() }
    }
}
#endif
