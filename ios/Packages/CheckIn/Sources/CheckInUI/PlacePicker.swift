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
    /// The kind a new squad place starts as: 健身 from a 训练, else 吃的.
    let newKind: SquadPlaceKind
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
            PlacePickerSheet(current: place, newKind: newKind) { picked in
                place = picked
                isPicking = false
            } cancel: {
                isPicking = false
            }
        }
    }
}

/// 添加位置: a short sheet with the map, its ticket pins, the search field and the places as rows.
/// A tap on a row or a pin only selects it (Tracy, 2026-11-13: she couldn't tell which pin a row
/// was): the map moves to it, its pin turns graphite under its name, its row darkens and the list
/// scrolls to it. 添加 in the header picks the selected place. The places the squad's members
/// added (自建地点) come first, with who added each; while typing, the last row adds what was
/// typed as a new one (Tracy, 2026-11-16; last, and only when no squad place has that name,
/// 2026-11-20),
/// on 新建地点 pushed in the sheet.
struct PlacePickerSheet: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.squadPlaces) private var book
    @State private var squadPlaces: [SquadPlace] = []
    /// What 新建地点 starts from, while it is pushed.
    @State private var creating: NewPlace?
    /// How tall the sheet stands: half the screen to pick, all of it for 新建地点's fields.
    @State private var detent: PresentationDetent = .medium
    @State private var search = PlaceSearch()
    @State private var query = ""
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    /// How far the map's camera is from the ground now, so moving to a place keeps the zoom.
    @State private var cameraDistance: Double?
    @State private var selected: FoundPlace?
    @State private var selections = 0
    /// The suggestion's title last put in the search field, so it doesn't ask for suggestions again.
    @State private var chosen: String?
    let newKind: SquadPlaceKind
    let pick: (Place) -> Void
    let cancel: () -> Void

    init(
        current: Place?, newKind: SquadPlaceKind, pick: @escaping (Place) -> Void, cancel: @escaping () -> Void
    ) {
        self.newKind = newKind
        self.pick = pick
        self.cancel = cancel
        _selected = State(initialValue: current.map { FoundPlace(place: $0, address: nil, distance: nil) })
    }

    private static let mapHeight: Double = 220
    /// The farthest the map stays when it moves to a selected place, so its pin stands apart.
    private static let closeUp: Double = 3000
    /// The nearest the map comes, so fitting one pin (a lone squad place while typing) shows its
    /// streets, not a rooftop.
    private static let nearest: Double = 500

    var body: some View {
        NavigationStack {
            picker
                .toolbarVisibility(.hidden, for: .navigationBar)
                .navigationDestination(item: $creating) { new in
                    if let wired = book.wired {
                        NewSquadPlacePage(new, source: wired.source, squad: wired.squad) { place in
                            squadPlaces.append(place)
                            pick(place.place)
                        }
                    }
                }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .onChange(of: creating) { _, new in
            if new != nil { detent = .large }
        }
        .task {
            guard let wired = book.wired else { return }
            if let places = try? await wired.source.places(in: wired.squad) { squadPlaces = places }
        }
    }

    private var picker: some View {
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
                    .accessibilityIdentifier("place.title")
            }
            .padding(.horizontal, Space.pageMargin)
            .padding(.vertical, Space.xs)
            ScrollViewReader { list in
                VStack(spacing: 0) {
                    map(list)
                    SearchField(text: $query, prompt: Text(copy: "搜索地点", bundle: .module))
                        .onSubmit {
                            Task {
                                let places = await search.placesForTyped()
                                reveal(places)
                            }
                        }
                        .padding(.horizontal, Space.pageMargin)
                        .padding(.vertical, Space.s)
                        .accessibilityIdentifier("place.search")
                    List {
                        ForEach(squadRows) { found in
                            Button {
                                select(found, list: nil)
                            } label: {
                                PlaceRow(found: found, isSelected: isSelected(found))
                            }
                            .listRowBackground(Color(role: isSelected(found) ? .bgSubtle : .bgCanvas, in: theme))
                            .accessibilityIdentifier("place.squad")
                        }
                        if search.isSuggesting {
                            ForEach(search.suggestions) { suggestion in
                                Button {
                                    choose(suggestion)
                                } label: {
                                    PlaceRow(
                                        symbol: "magnifyingglass", name: suggestion.title, detail: suggestion.subtitle,
                                        distance: nil, isSelected: false)
                                }
                                .listRowBackground(Color(role: .bgCanvas, in: theme))
                                .accessibilityIdentifier("place.suggestion")
                            }
                        } else {
                            ForEach(search.found) { found in
                                Button {
                                    select(found, list: nil)
                                } label: {
                                    PlaceRow(found: found, isSelected: isSelected(found))
                                }
                                .listRowBackground(Color(role: isSelected(found) ? .bgSubtle : .bgCanvas, in: theme))
                                .accessibilityIdentifier("place.row")
                            }
                        }
                        if search.isSuggesting, book.wired != nil, let typed = newName {
                            Button {
                                // Where the phone is, else the place selected or the squad's first, so the map
                                // opens near.
                                creating = NewPlace(
                                    name: typed,
                                    kind: newKind,
                                    near: search.here?.coordinate ?? selected?.coordinate ?? squadRows.first?.coordinate
                                )
                            } label: {
                                PlaceRow(
                                    symbol: "plus", name: String(copy: "新建「\(typed)」", bundle: .module), detail: nil,
                                    distance: nil, isSelected: false)
                            }
                            .listRowBackground(Color(role: .bgCanvas, in: theme))
                            .accessibilityIdentifier("place.new")
                        }
                    }
                    .listStyle(.plain)
                    .scrollDismissesKeyboard(.immediately)
                }
            }
        }
        .background(Color(role: .bgCanvas, in: theme).ignoresSafeArea())
        .haptic(.pick, trigger: selections)
        .task { await search.lookAround() }
        .onChange(of: query) { _, query in
            // A suggestion's title put in the field is no new typing.
            guard query != chosen else { return }
            chosen = nil
            search.type(query)
            if query.isEmpty, search.here != nil { camera = .userLocation(fallback: .automatic) }
        }
    }

    /// A suggestion tapped: its title goes in the field, as in Apple Maps, and the places it finds
    /// replace the list. One place is selected at once; a kind of place's many fill the map.
    private func choose(_ suggestion: Suggestion) {
        chosen = suggestion.title
        query = suggestion.title
        let id = suggestion.id
        Task {
            let places = await search.places(forSuggestion: id)
            reveal(places)
        }
    }

    /// The places a search found, now the list: one is selected at once, many fill the map.
    private func reveal(_ places: [FoundPlace]) {
        if places.count == 1, let only = places.first {
            select(only, list: nil)
        } else if !places.isEmpty {
            // A search's places may be anywhere, so the map fits them.
            withAnimation(.wildcard(Motion.page, reduceMotion: reduceMotion)) { camera = .automatic }
        }
    }

    private func map(_ list: ScrollViewProxy) -> some View {
        Map(position: $camera, bounds: MapCameraBounds(minimumDistance: Self.nearest)) {
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

    /// The found places and the squad's own, the selected one last so it draws over its
    /// neighbours, and kept on the map when a new search no longer finds it.
    private var pins: [FoundPlace] {
        let all = squadRows + search.found
        guard let selected else { return all }
        return all.filter { $0.id != selected.id } + [selected]
    }

    /// What was typed, as a new place's name; nil while nothing is, or while one of the squad's
    /// places has that name. Maps' suggestions don't count: its autocomplete offers what was
    /// typed back as a search term (「健身房」 → 健身房 · 搜索附近), which would hide 新建 for
    /// almost any word.
    private var newName: String? {
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return nil }
        let taken = squadRows.contains {
            $0.place.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .compare(typed, options: [.caseInsensitive, .widthInsensitive]) == .orderedSame
        }
        return taken ? nil : typed
    }

    /// The squad's own places that have what was typed in their name, as rows: under each, who
    /// added it.
    private var squadRows: [FoundPlace] {
        squadPlaces.filter { $0.matches(query) }.map { added in
            let location = CLLocation(latitude: added.place.latitude, longitude: added.place.longitude)
            return FoundPlace(
                place: added.place,
                address: added.addedBy.flatMap(book.name).map { String(copy: "\($0)添加", bundle: .module) },
                distance: search.here.map { $0.distance(from: location) })
        }
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
        selected = (squadRows + search.found).first { $0.id == found.id } ?? found
        let distance = min(cameraDistance ?? Self.closeUp, Self.closeUp)
        withAnimation(.wildcard(Motion.page, reduceMotion: reduceMotion)) {
            camera = .camera(MapCamera(centerCoordinate: found.coordinate, distance: distance))
            if let list, (squadRows + search.found).contains(where: { $0.id == found.id }) {
                list.scrollTo(found.id, anchor: .top)
            }
        }
    }
}
#endif
