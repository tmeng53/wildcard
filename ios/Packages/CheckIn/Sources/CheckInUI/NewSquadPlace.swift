#if os(iOS)
import CheckInDomain
import Contracts
import DesignSystem
import DesignSystemUI
import MapKit
import SwiftUI

/// 新建地点, pushed in 添加位置 from 「新建「…」」 when Apple Maps doesn't list the place (公司食堂,
/// 小区健身房; Tracy, 2026-11-16): the map under a pin that stays in its middle, so the member drags
/// the map to put the place under it, the name they typed, and 吃的, 健身 or 户外. 添加 adds it for
/// the squad and picks it at once. Only the squad sees it.
struct NewSquadPlacePage: View {
    @Environment(\.sceneTheme) private var theme
    @State private var name: String
    @State private var kind: SquadPlaceKind?
    @State private var camera: MapCameraPosition
    @State private var center: CLLocationCoordinate2D?
    @State private var isAdding = false
    @State private var failed = false
    /// Made once, so trying again after a failure adds the place once.
    @State private var id = UUID()
    let source: any SquadPlaceSource
    let squad: SquadID
    let added: (SquadPlace) -> Void

    init(
        _ new: NewPlace, source: any SquadPlaceSource, squad: SquadID, added: @escaping (SquadPlace) -> Void
    ) {
        let start = new.near
        _name = State(initialValue: new.name)
        _center = State(initialValue: start)
        _camera = State(
            initialValue: start.map { .camera(MapCamera(centerCoordinate: $0, distance: Self.distance)) }
                ?? .userLocation(fallback: .automatic))
        (self.source, self.squad, self.added) = (source, squad, added)
    }

    /// Close enough to tell one building from the next.
    private static let distance: Double = 800
    private static let mapHeight: Double = 280

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                map
                VStack(alignment: .leading, spacing: Space.l) {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        fieldLabel(Text(copy: "名字", bundle: .module))
                        InputField(text: $name, label: Text(copy: "名字", bundle: .module))
                            .accessibilityIdentifier("newPlace.name")
                    }
                    VStack(alignment: .leading, spacing: Space.xs) {
                        fieldLabel(Text(copy: "类型", bundle: .module))
                        HStack(spacing: Space.xs) {
                            ForEach(SquadPlaceKind.allCases, id: \.self) { kind in
                                PickPill(
                                    kind.title, systemImage: kind.symbol, look: .outlined, isSelected: self.kind == kind
                                ) {
                                    self.kind = kind
                                }
                                .accentTone(.ink)
                                .accessibilityIdentifier("newPlace.kind.\(kind.rawValue)")
                            }
                        }
                    }
                    if failed {
                        Text(copy: "没加上，再试一次", bundle: .module)
                            .typeStyle(TypeRamp.footnote)
                            .foregroundStyle(Color(role: .fgDanger, in: theme))
                    }
                    Text(copy: "仅小队可见", bundle: .module)
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                }
                .padding(.horizontal, Space.pageMargin)
                .padding(.vertical, Space.l)
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .background(Color(role: .bgCanvas, in: theme).ignoresSafeArea())
        .navigationTitle(Text(copy: "新建地点", bundle: .module))
        .pushedPage()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await add() }
                } label: {
                    if isAdding {
                        ProgressView()
                    } else {
                        Text(copy: "添加", bundle: .module)
                    }
                }
                .buttonStyle(.glassProminent)
                .tint(Color(role: .fgDefault, in: theme))
                .disabled(draft == nil || isAdding)
                .accessibilityIdentifier("newPlace.add")
            }
        }
    }

    private func fieldLabel(_ text: Text) -> some View {
        text
            .typeStyle(TypeRamp.footnoteEmphasis)
            .foregroundStyle(Color(role: .fgMuted, in: theme))
            .accessibilityHidden(true)
    }

    /// The map, with the place's pin fixed in its middle: dragging the map moves the place.
    private var map: some View {
        Map(position: $camera) {
            UserAnnotation()
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .onMapCameraChange(frequency: .continuous) { context in center = context.camera.centerCoordinate }
        .overlay {
            // The pin's foot on the map's middle.
            TicketPin(symbol: (kind ?? .food).symbol, isPicked: true)
                .alignmentGuide(VerticalAlignment.center) { $0[.bottom] }
                .allowsHitTesting(false)
        }
        .frame(height: Self.mapHeight)
        .accessibilityIdentifier("newPlace.map")
    }

    /// What 添加 sends: a name the API takes, a kind and where the pin stands.
    private var draft: NewSquadPlace? {
        guard let kind, let center else { return nil }
        return try? NewSquadPlace(name: name, kind: kind, latitude: center.latitude, longitude: center.longitude)
    }

    private func add() async {
        guard let draft else { return }
        (isAdding, failed) = (true, false)
        defer { isAdding = false }
        do throws(SquadPlacesError) {
            let place = try await source.add(draft, id: id, to: squad)
            added(place)
        } catch {
            failed = true
        }
    }
}

extension SquadPlaceKind {
    /// 吃的, 健身 or 户外.
    var title: Text {
        switch self {
        case .food: Text(copy: "吃的", bundle: .module)
        case .gym: Text(copy: "健身", bundle: .module)
        case .outdoor: Text(copy: "户外", bundle: .module)
        }
    }
}
#endif
