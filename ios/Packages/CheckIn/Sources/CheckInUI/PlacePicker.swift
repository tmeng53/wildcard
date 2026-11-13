#if os(iOS)
import CheckInDomain
import Contracts
import DesignSystem
import DesignSystemUI
import LocationUI
import MapKit
import SwiftUI

/// 添加位置 on the compose ticket, left of the caption's count (Tracy, 2026-11-12): unpicked, a
/// pill that opens the map; picked, the place's name on graphite with ✕ to take it off and the
/// name opening the place's page.
struct PlacePill: View {
    @Binding var place: Place?
    /// Opens the picked place's page (地点页).
    let open: (Place) -> Void
    @State private var isPicking = false

    var body: some View {
        Group {
            if let place {
                // Only the cross takes the place off; the name opens the place's page.
                PickPill(
                    Text(verbatim: place.name), systemImage: place.kind.symbol, look: .solid, isSelected: true
                ) {
                    open(place)
                } remove: {
                    self.place = nil
                }
                .accentTone(.ink)
            } else {
                PickPill(Text(copy: "添加位置", bundle: .module), systemImage: "mappin", look: .solid, isSelected: false) {
                    isPicking = true
                }
                .accessibilityIdentifier("compose.place")
            }
        }
        .sheet(isPresented: $isPicking) {
            PlacePickerSheet(current: place) { picked in
                place = picked
                isPicking = false
            } cancel: {
                isPicking = false
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}

/// One place Apple Maps found, as a row and a pin show it.
struct FoundPlace: Identifiable, Hashable, Sendable {
    let place: Place
    let address: String?
    /// Metres from the phone, when the phone's place is known.
    let distance: Double?

    var id: String { place.appleID ?? "\(place.name)|\(place.latitude)|\(place.longitude)" }
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
    }
}

/// The places around the phone, then the ones a typed search finds, through MapKit. The phone's
/// position is used only on the phone, to search near it; only the picked place goes in the post.
@MainActor
@Observable
final class PlaceSearch {
    private(set) var found: [FoundPlace] = []
    private(set) var here: CLLocation?
    private var nearby: [FoundPlace] = []
    /// What the member typed, so the nearby list never replaces a search's results.
    private var typed = ""

    /// How far around the phone the nearby list looks.
    private static let radius: CLLocationDistance = 1000

    func lookAround() async {
        guard let near = await CoreLocationReader(locale: { AppLanguage.current.locale }).nearHere() else { return }
        let location = CLLocation(latitude: near.latitude, longitude: near.longitude)
        here = location
        let request = MKLocalPointsOfInterestRequest(center: location.coordinate, radius: Self.radius)
        nearby = await places(MKLocalSearch(request: request))
        if typed.isEmpty { found = nearby }
    }

    func search(_ query: String) async {
        typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else {
            found = nearby
            return
        }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = typed
        request.resultTypes = [.pointOfInterest, .address]
        if let here {
            request.region = MKCoordinateRegion(
                center: here.coordinate, latitudinalMeters: Self.radius * 20, longitudinalMeters: Self.radius * 20)
        }
        let results = await places(MKLocalSearch(request: request))
        guard !Task.isCancelled else { return }
        found = results
    }

    /// Through the completion handler on the main queue, as `RouteSnapshot` does, so nothing
    /// MapKit hands back crosses an actor.
    private func places(_ search: MKLocalSearch) async -> [FoundPlace] {
        let here = here
        return await withCheckedContinuation { continuation in
            search.start { response, _ in
                continuation.resume(returning: Self.found(in: response, near: here))
            }
        }
    }

    private static func found(in response: MKLocalSearch.Response?, near here: CLLocation?) -> [FoundPlace] {
        guard let response else { return [] }
        return response.mapItems.compactMap { item in
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
        .sorted { ($0.distance ?? .infinity) < ($1.distance ?? .infinity) }
    }
}

/// 添加位置: a short sheet with the map, its ticket pins, the search field and the places as rows.
/// A tap on a row or a pin only selects it (Tracy, 2026-11-13: she couldn't tell which pin a row
/// was): the map moves to it, its pin turns graphite under its name, its row darkens and the list
/// scrolls to it. 添加 in the header picks the selected place.
struct PlacePickerSheet: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var search = PlaceSearch()
    @State private var query = ""
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    /// How far the map's camera is from the ground now, so moving to a place keeps the zoom.
    @State private var cameraDistance: Double?
    @State private var selected: FoundPlace?
    @State private var selections = 0
    let pick: (Place) -> Void
    let cancel: () -> Void

    init(current: Place?, pick: @escaping (Place) -> Void, cancel: @escaping () -> Void) {
        self.pick = pick
        self.cancel = cancel
        _selected = State(initialValue: current.map { FoundPlace(place: $0, address: nil, distance: nil) })
    }

    private static let mapHeight: Double = 220
    /// The farthest the map stays when it moves to a selected place, so its pin stands apart.
    private static let closeUp: Double = 3000

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                HeaderTextButton(Text(copy: "取消", bundle: .module), action: cancel)
                    .accessibilityIdentifier("place.cancel")
                Spacer()
                HeaderTextButton(Text(copy: "添加", bundle: .module), prominent: true) {
                    if let selected { pick(selected.place) }
                }
                .disabled(selected == nil)
                .accentTone(.ink)
                .accessibilityIdentifier("place.add")
            }
            .overlay {
                Text(copy: "添加位置", bundle: .module)
                    .typeStyle(TypeRamp.headline)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .accessibilityAddTraits(.isHeader)
            }
            .padding(.horizontal, Space.pageMargin)
            .padding(.vertical, Space.xs)
            ScrollViewReader { list in
                VStack(spacing: 0) {
                    map(list)
                    SearchField(text: $query, prompt: Text(copy: "搜索地点", bundle: .module))
                        .padding(.horizontal, Space.pageMargin)
                        .padding(.vertical, Space.s)
                        .accessibilityIdentifier("place.search")
                    List(search.found) { found in
                        Button {
                            select(found, list: nil)
                        } label: {
                            PlaceRow(found: found, isSelected: isSelected(found))
                        }
                        .listRowBackground(Color(role: isSelected(found) ? .bgSubtle : .bgCanvas, in: theme))
                        .accessibilityIdentifier("place.row")
                    }
                    .listStyle(.plain)
                    .scrollDismissesKeyboard(.immediately)
                }
            }
        }
        .background(Color(role: .bgCanvas, in: theme).ignoresSafeArea())
        .haptic(.pick, trigger: selections)
        .task { await search.lookAround() }
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await search.search(query)
        }
        .onChange(of: search.found) { _, found in
            // Nearby places sit around the phone; a search's may be anywhere, so the map fits them.
            guard !found.isEmpty else { return }
            camera = query.isEmpty && search.here != nil ? .userLocation(fallback: .automatic) : .automatic
        }
    }

    private func map(_ list: ScrollViewProxy) -> some View {
        Map(position: $camera) {
            UserAnnotation()
            ForEach(pins) { found in
                Annotation(found.place.name, coordinate: found.coordinate, anchor: .bottom) {
                    VStack(spacing: Space.xxs) {
                        if isSelected(found) { PinName(name: found.place.name) }
                        TicketPin(symbol: found.place.kind.symbol, isPicked: isSelected(found))
                    }
                    .onTapGesture { select(found, list: list) }
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .onMapCameraChange { context in cameraDistance = context.camera.distance }
        .frame(height: Self.mapHeight)
    }

    /// The found places, the selected one last so it draws over its neighbours, and kept on the
    /// map when a new search no longer finds it.
    private var pins: [FoundPlace] {
        guard let selected else { return search.found }
        return search.found.filter { $0.id != selected.id } + [selected]
    }

    private func isSelected(_ found: FoundPlace) -> Bool {
        guard let selected else { return false }
        if let id = selected.place.appleID { return id == found.place.appleID }
        return selected.place == found.place
    }

    /// Selects a place: the map moves to it at the zoom it has (no farther than `closeUp`), and a
    /// pin's tap scrolls the list to its row. The tap itself puts the keyboard away (the app's
    /// `dismissesKeyboardOnTapOutside`).
    private func select(_ found: FoundPlace, list: ScrollViewProxy?) {
        if !isSelected(found) { selections += 1 }
        // A row's details (address, distance) win over the bare place a post came in with.
        selected = search.found.first { $0.id == found.id } ?? found
        let distance = min(cameraDistance ?? Self.closeUp, Self.closeUp)
        withAnimation(.wildcard(Motion.page, reduceMotion: reduceMotion)) {
            camera = .camera(MapCamera(centerCoordinate: found.coordinate, distance: distance))
            if let list, search.found.contains(where: { $0.id == found.id }) {
                list.scrollTo(found.id, anchor: .top)
            }
        }
    }
}

/// The selected pin's name over it, in graphite like the pin.
private struct PinName: View {
    @Environment(\.sceneTheme) private var theme
    let name: String

    var body: some View {
        Text(verbatim: name)
            .typeStyle(TypeRamp.footnoteEmphasis)
            .foregroundStyle(Color(role: .bgCanvas, in: theme))
            .lineLimit(1)
            .padding(.horizontal, Space.s)
            .padding(.vertical, Space.xxs)
            .background(Color(role: .fgDefault, in: theme), in: Capsule())
            .accessibilityHidden(true)
    }
}

/// A place in the list: its kind's icon in a circle, its name and address, and how far it is.
private struct PlaceRow: View {
    @Environment(\.sceneTheme) private var theme
    let found: FoundPlace
    let isSelected: Bool

    private static let disc: Double = 36

    var body: some View {
        HStack(spacing: Space.s) {
            Image(systemName: found.place.kind.symbol)
                .font(.system(size: Sizing.smallIcon, weight: .semibold))
                .foregroundStyle(Color(role: isSelected ? .bgCanvas : .fgDefault, in: theme))
                .frame(width: Self.disc, height: Self.disc)
                .background(Color(role: isSelected ? .fgDefault : .bgSubtle, in: theme), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(verbatim: found.place.name)
                    .typeStyle(TypeRamp.pick)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .lineLimit(1)
                if let address = found.address {
                    Text(verbatim: address)
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let distance = found.distance {
                Text(verbatim: Self.distance(distance))
                    .typeStyle(TypeRamp.scoreCaption)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .monospacedDigit()
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    static func distance(_ metres: Double) -> String {
        Measurement(value: metres, unit: UnitLength.meters)
            .formatted(
                .measurement(
                    width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(0...1))
                )
                .locale(AppLanguage.current.locale))
    }
}

/// A map pin shaped as the logo's ticket: a stub under a notched tear line, the place's kind's
/// icon above it. Graphite once it is the picked place, else white with a hairline.
struct TicketPin: View {
    @Environment(\.sceneTheme) private var theme
    let symbol: String
    let isPicked: Bool

    private static let size = CGSize(width: 32, height: 46)
    /// The tear line, from the top: the face is a square above it.
    private static let tear: Double = 32

    var body: some View {
        let shape = PinTicket(tear: Self.tear)
        ZStack(alignment: .top) {
            shape.fill(Color(role: isPicked ? .fgDefault : .bgCanvas, in: theme))
            shape.stroke(Color(role: isPicked ? .fgDefault : .borderDefault, in: theme), lineWidth: Sizing.hairline)
            Image(systemName: symbol)
                .font(.system(size: Sizing.smallIcon, weight: .semibold))
                .foregroundStyle(Color(role: isPicked ? .bgCanvas : .fgDefault, in: theme))
                .frame(width: Self.size.width, height: Self.tear)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .shadow(color: Color(role: .fgDefault, in: theme).opacity(0.15), radius: 3, y: 1)
        .accessibilityHidden(true)
    }
}

/// The ticket's outline at pin size: rounded corners and a half-round notch in each side.
private struct PinTicket: Shape {
    let tear: Double
    private let notch: Double = 3.5
    private let corner: Double = 6

    func path(in rect: CGRect) -> Path {
        let ticket = Path(roundedRect: rect, cornerRadius: corner, style: .continuous)
        var notches = Path()
        for side in [rect.minX, rect.maxX] {
            notches.addEllipse(
                in: CGRect(x: side - notch, y: rect.minY + tear - notch, width: notch * 2, height: notch * 2))
        }
        return ticket.subtracting(notches)
    }
}
#endif
