#if os(iOS)
import AvatarDomain
import AvatarUI
import CheckInDomain
import Contracts
import DesignSystem
import DesignSystemUI
import MapKit
import PlacesDomain
import SportsUI
import SwiftUI

/// 动态's map button, left of the bell (Tracy, 2026-11-12): the same round header button, a map
/// for its icon. Everything on the map comes from 动态's posts, so 动态 is the only way in.
public struct SquadMapButton: View {
    private let open: () -> Void

    public init(open: @escaping () -> Void) {
        self.open = open
    }

    public var body: some View {
        HeaderButton(Text(copy: "小队地图", bundle: .module), systemImage: "map", action: open)
            .accessibilityIdentifier("squadMap.open")
    }
}

/// 小队地图 as 动态 pushes it: makes the map's store once, the first time the page is drawn, so
/// going to a place and back keeps what it read.
public struct SquadMapScreen: View {
    @State private var store: SquadMapStore
    private let openPlace: (Place) -> Void
    private let openPost: (CheckInID) -> Void

    /// - Parameters:
    ///   - today: the reader's today, whose posts 今天 shows.
    ///   - openPlace: a place's name was tapped: its 地点页.
    ///   - openPost: one of a member's posts was tapped: its own page.
    public init(
        squad: SquadID, today: LocalDay, source: any PlaceSource, openPlace: @escaping (Place) -> Void,
        openPost: @escaping (CheckInID) -> Void
    ) {
        _store = State(initialValue: SquadMapStore(squad: squad, today: today, source: source))
        (self.openPlace, self.openPost) = (openPlace, openPost)
    }

    public var body: some View {
        SquadMapPage(store: store, openPlace: openPlace, openPost: openPost)
    }
}

/// 小队地图 (Tracy, 2026-11-12): the squad's places on a map over a list, 今天 or 常去. Teammates at
/// one place stack their heads like the 战报's map, with no tickets or pins; a tap fans the stack
/// out into a row, a tight line (name and time, or how often) under each head and the place's
/// white capsule right under them, which opens its page. 今天's list runs newest first, and a
/// row puts that member's day alone on the map (their head in a black ring over a capsule of
/// place, time and what they did there, everyone else faded) with only their posts below, until
/// ✕. 常去 marks each place with how often the squad went, the most visited bigger and named,
/// the rarely visited fainter. No scores anywhere (Tracy, 2026-11-13).
struct SquadMapPage: View {
    @Bindable var store: SquadMapStore
    let openPlace: (Place) -> Void
    let openPost: (CheckInID) -> Void
    @State private var heads = AuthorHeads()
    @State private var camera = MapCameraPosition.automatic
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            Picker(selection: $store.mode) {
                Text(copy: "今天", bundle: .module).tag(SquadMapLayout.Mode.today)
                Text(copy: "常去", bundle: .module).tag(SquadMapLayout.Mode.often)
            } label: {
                Text(copy: "小队地图", bundle: .module)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Space.pageMargin)
            .padding(.vertical, Space.xs)
            .accessibilityIdentifier("squadMap.mode")
            map
            SquadMapList(store: store, heads: heads, openPlace: openPlace, openPost: openPost)
                .frame(height: Self.listHeight)
        }
        .background(Color(role: .bgCanvas, in: theme))
        .navigationTitle(Text(copy: "小队地图", bundle: .module))
        .pushedPage()
        .task { await store.load() }
        .onChange(of: framing) { _, _ in fit() }
        .accessibilityIdentifier("squadMap.page")
    }

    private var map: some View {
        Map(position: $camera) {
            if store.member == nil {
                ForEach(store.spots) { spot in
                    Annotation(spot.place.place.name, coordinate: spot.place.place.coordinate, anchor: .top) {
                        SpotMarker(
                            spot: spot, mode: store.mode, expanded: store.expanded == spot.id, store: store,
                            heads: heads,
                            toggle: {
                                withAnimation(.wildcard(Motion.change, reduceMotion: reduceMotion)) {
                                    store.toggle(spot.id)
                                }
                            },
                            openPlace: { openPlace(spot.place.place) })
                    }
                    .annotationTitles(.hidden)
                }
            } else {
                // Everyone else's stacks, faded behind the member's day.
                ForEach(store.fadedSpots) { spot in
                    Annotation(spot.place.place.name, coordinate: spot.place.place.coordinate, anchor: .top) {
                        HeadPile(players: spot.heads.map(player(for:)), size: SpotMarker.headSize)
                            .opacity(0.3)
                            .allowsHitTesting(false)
                    }
                    .annotationTitles(.hidden)
                }
                ForEach(store.stops) { stop in
                    Annotation(stop.place.place.name, coordinate: stop.place.place.coordinate, anchor: .top) {
                        StopMarker(stop: stop, head: player(for: stop.visit.author)) {
                            openPlace(stop.place.place)
                        }
                    }
                    .annotationTitles(.hidden)
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls { MapCompass() }
        .frame(maxHeight: .infinity)
    }

    private func player(for member: MemberID) -> CharacterPlayer? {
        heads.player(for: store.characters[member]?.look)
    }

    /// What the camera frames: the places on the map now.
    private var framing: [PlaceKey] {
        store.member == nil ? store.spots.map(\.id) : store.stops.map(\.place.key)
    }

    /// Frames every place on the map, a little wider than they reach; nothing on it leaves the
    /// camera where it is.
    private func fit() {
        let places = store.member == nil ? store.spots.map(\.place.place) : store.stops.map(\.place.place)
        guard let region = MKCoordinateRegion(fitting: places) else { return }
        withAnimation(.wildcard(Motion.page, reduceMotion: reduceMotion)) { camera = .region(region) }
    }

    /// The list's height under the map.
    private static var listHeight: Double { 300 }
}

/// A stack of heads at a place, or the row it fans out into.
private struct SpotMarker: View {
    let spot: MapSpot
    let mode: SquadMapLayout.Mode
    let expanded: Bool
    let store: SquadMapStore
    let heads: AuthorHeads
    let toggle: () -> Void
    let openPlace: () -> Void
    @Environment(\.sceneTheme) private var theme

    static let headSize: Double = 36

    var body: some View {
        Group {
            if expanded {
                VStack(spacing: Space.xxs) {
                    HStack(alignment: .top, spacing: Space.xs) {
                        ForEach(entries, id: \.member) { entry in
                            VStack(spacing: Space.xxs) {
                                MemberHead(
                                    player: heads.player(for: store.characters[entry.member]?.look), size: Self.headSize
                                )
                                .greyed(!store.isInSquad(entry.member))
                                Text(verbatim: entry.line)
                                    .typeStyle(TypeRamp.caption)
                                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                        }
                    }
                    .onTapGesture(perform: toggle)
                    PlaceCapsule(text: spot.place.place.name, action: openPlace)
                }
            } else {
                VStack(spacing: Space.xxs) {
                    Button(action: toggle) {
                        HeadPile(
                            players: spot.heads.map { heads.player(for: store.characters[$0]?.look) },
                            size: spot.emphasis == .top ? Self.headSize + 8 : Self.headSize,
                            greyed: spot.heads.map { !store.isInSquad($0) }
                        )
                        .overlay(alignment: .topTrailing) {
                            if mode == .often { VisitBadge(count: spot.place.visits) }
                        }
                    }
                    .buttonStyle(.plain)
                    if spot.emphasis == .top {
                        PlaceCapsule(text: spot.place.place.name, action: openPlace)
                    }
                }
                .opacity(spot.emphasis == .faint ? 0.55 : 1)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: spot.place.place.name))
        .accessibilityIdentifier("squadMap.spot")
    }

    /// Who is in the row, each once: 今天 with the time of their newest post there, 常去 with how
    /// many times they went.
    private var entries: [(member: MemberID, line: String)] {
        switch mode {
        case .today:
            var seen = Set<MemberID>()
            return spot.visits.filter { seen.insert($0.author).inserted }.map { visit in
                (visit.author, "\(name(of: visit.author)) \(visit.createdAt.date.formatted(MapVisit.clock))")
            }
        case .often:
            return spot.place.members.map { each in
                (each.member, "\(name(of: each.member)) \(each.visits)\(String(copy: "次", bundle: .module))")
            }
        }
    }

    private func name(of member: MemberID) -> String {
        store.characters[member]?.nickname.text ?? String(copy: "队友", bundle: .module)
    }

}

/// Heads piled at one spot, each a little down and right of the one over it, the first on top.
private struct HeadPile: View {
    let players: [CharacterPlayer?]
    let size: Double
    var greyed: [Bool] = []

    var body: some View {
        let shown = Array(players.prefix(3).enumerated())
        ZStack(alignment: .topLeading) {
            ForEach(shown.reversed(), id: \.offset) { index, player in
                MemberHead(player: player, size: size, rim: .cutout(.bgCanvas))
                    .greyed(greyed.indices.contains(index) && greyed[index])
                    .offset(x: Double(index) * size * 0.3, y: Double(index) * size * 0.18)
            }
        }
        .frame(
            width: size * (1 + 0.3 * Double(max(shown.count - 1, 0))),
            height: size * (1 + 0.18 * Double(max(shown.count - 1, 0))), alignment: .topLeading
        )
        .accessibilityHidden(true)
    }
}

/// How often the squad went: a small graphite disc at a stack's corner.
private struct VisitBadge: View {
    let count: Int
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        Text(verbatim: "\(count)")
            .typeStyle(TypeRamp.label)
            .monospacedDigit()
            .foregroundStyle(Color(role: .fgOnBrand, in: theme))
            .padding(.horizontal, Space.xxs)
            .frame(minWidth: 20, minHeight: 20)
            .background(Color(role: .bgBrand, in: theme), in: Capsule())
            .overlay(Capsule().strokeBorder(Color(role: .bgCanvas, in: theme), lineWidth: Sizing.selectionStroke))
            .offset(x: 6, y: -6)
            .accessibilityHidden(true)
    }
}

/// A place's name in a white capsule under its heads; a tap opens its 地点页.
private struct PlaceCapsule: View {
    let text: String
    let action: () -> Void
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        Button(action: action) {
            Text(verbatim: text)
                .typeStyle(TypeRamp.footnoteEmphasis)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .lineLimit(1)
                .padding(.horizontal, Space.s - 2)
                .padding(.vertical, Space.xxs)
                .background(Color(role: .bgCanvas, in: theme), in: Capsule())
                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                .fixedSize()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("squadMap.place")
    }
}

/// One of a member's posts today on their map: their head in a black ring, and right under it a
/// capsule of the place, the time and what they did there, which opens the place.
private struct StopMarker: View {
    let stop: MapStop
    let head: CharacterPlayer?
    let openPlace: () -> Void
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        VStack(spacing: Space.xxs) {
            MemberHead(player: head, size: SpotMarker.headSize)
                .overlay(Circle().strokeBorder(Color(role: .fgDefault, in: theme), lineWidth: 2.5))
            PlaceCapsule(text: line, action: openPlace)
        }
    }

    private var line: String {
        let time = stop.visit.createdAt.date.formatted(MapVisit.clock)
        return "\(stop.place.place.name) · \(time) \(stop.visit.doing)"
    }
}

extension Place {
    fileprivate var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

extension MKCoordinateRegion {
    /// A region around every place, with room at the edges for the heads; nil for none.
    fileprivate init?(fitting places: [Place]) {
        guard let first = places.first else { return nil }
        var (south, north, west, east) = (first.latitude, first.latitude, first.longitude, first.longitude)
        for place in places.dropFirst() {
            (south, north) = (min(south, place.latitude), max(north, place.latitude))
            (west, east) = (min(west, place.longitude), max(east, place.longitude))
        }
        self.init(
            center: CLLocationCoordinate2D(latitude: (south + north) / 2, longitude: (west + east) / 2),
            span: MKCoordinateSpan(
                latitudeDelta: max((north - south) * 1.6, 0.01), longitudeDelta: max((east - west) * 1.6, 0.01)))
    }
}

#endif
