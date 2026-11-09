#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import CharacterEditorDomain
import DesignSystem
import DesignSystemUI
import SportsUI
import SwiftUI

/// 商店街 as a street (逛街版, approved 2026-11-06; drawn as a scene 2026-11-08): the stores side by
/// side under a pale sky, one storefront at a time in the middle with its neighbours peeking in,
/// paged by the system's scroll. The member stands on the paved street under it. The street's map,
/// the centred store's sports and its button are `StreetCounter`, a white sheet pinned at the
/// page's bottom. The street takes the height it is given: the storefronts' windows grow on a tall
/// phone, from the size the lockup needs, so the street fills the page.
struct StoreStreet: View {
    let model: StreetModel
    /// The store in the middle, which the page's counter shows.
    @Binding var current: String?
    /// The street is sliding, by a swipe or a tap on its map: the member strolls.
    @State private var walking = false
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How much of each neighbour peeks in at the screen's edges.
    private let peek: Double = 48
    private let character = CGSize(width: 100, height: 134)
    /// The paved street showing above the counter, its kerb included.
    private let street: Double = 142

    var body: some View {
        let stores = model.catalog.stores
        ZStack(alignment: .bottom) {
            ShopPavement()
                .frame(height: street)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .bottom, spacing: Space.s) {
                    ForEach(stores) { store in
                        Storefront(model: model, store: store)
                            // The container is the scroll view less its content margins, so a
                            // storefront as wide as it leaves a neighbour peeking in either side.
                            .containerRelativeFrame(.horizontal)
                            .id(store.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $current)
            .contentMargins(.horizontal, peek, for: .scrollContent)
            .scrollIndicators(.hidden)
            .onScrollPhaseChange { _, phase in walking = phase.isScrolling }
            .padding(.bottom, street)
            walker
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
        // The street runs to the screen's edges, past the page's margins.
        .padding(.horizontal, -Space.pageMargin)
    }

    /// The member with their shopping bags on the street under the store in the middle, strolling
    /// while the street slides and, once it stops, spotting something in the window.
    private var walker: some View {
        ShopperView(look: model.draft.outfit, persona: model.draft.persona, walking: walking && !reduceMotion)
            .frame(width: character.width, height: character.height)
            .background(alignment: .bottom) {
                Ellipse()
                    .fill(Color(role: .bgInk, in: theme).opacity(0.1))
                    .frame(width: 70, height: 12)
            }
            .padding(.bottom, Space.xs - Space.xxs / 2)
    }
}

/// The street's counter, a white sheet pinned at the bottom of 商店街 above the tab bar: the map,
/// the centred store's sports and its button, 进店 when open, how it unlocks when not.
struct StreetCounter: View {
    let model: StreetModel
    let store: EditorChoices.Store
    /// Walks the street to a store, from its badge on the map.
    let walk: (String) -> Void

    var body: some View {
        VStack(spacing: Space.s) {
            StreetMap(model: model, current: store.id, walk: walk)
            sports(store.id)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("street.sports")
            if store.isOpen {
                Button {
                    model.visit(store)
                } label: {
                    Text(copy: "进店", bundle: .module).frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .accentTone(.brand)
                .accessibilityIdentifier("street.enter")
            } else {
                Button {
                } label: {
                    StoreCopy.opens(store).frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(true)
                .accessibilityIdentifier("street.enter")
            }
        }
        .padding(.horizontal, Space.pageMargin)
        .padding(.top, Space.xs)
        .padding(.bottom, Space.s)
    }

    /// The sports its pieces' rules count as pills, as its tip lists them, or its own line's
    /// sports where none has one. It always takes two lines' room, so the street above stays put
    /// as it pages from a store with one line of sports to one with two.
    private func sports(_ store: String) -> some View {
        ZStack {
            VStack(spacing: Space.xs) {
                SportPill(word: Text(verbatim: " "))
                SportPill(word: Text(verbatim: " "))
            }
            .hidden()
            sportPills(store)
        }
    }

    private func sportPills(_ store: String) -> some View {
        FlowRow(spacing: Space.xs, centred: true) {
            if let sports = model.sports(of: store) {
                if sports.isEmpty {
                    SportPill(word: Text(copy: "什么运动都行", bundle: .module))
                } else {
                    ForEach(sports, id: \.self) { SportPill(word: $0.name) }
                }
            } else {
                ForEach(StoreCopy.sports(store), id: \.self) { SportPill(word: Text(verbatim: $0)) }
            }
        }
    }
}

/// One store's front, drawn like the App Store screenshots' shops (approved 2026-11-08): a cap in
/// the store's dark colour, its sign, the striped awning, the wall in a tint of its colour with
/// the window (the model on its plinth) and the door, and a step down to the street. A store with something new hangs NEW on its door; a closed one is grey,
/// says 「? ? ?」 and has its shutter down. A tap on an open one walks in.
private struct Storefront: View {
    let model: StreetModel
    let store: EditorChoices.Store
    @Environment(\.sceneTheme) private var theme
    @State private var width: Double = 0

    /// The wall grows with the street's height, from what the window's model needs.
    private let wall: ClosedRange<Double> = 196...330
    private let frame: Double = 6
    private let door: Double = 64
    private let figure = CGSize(width: 116, height: 155)

    var body: some View {
        let open = store.isOpen
        let color = open ? StoreLook.color(store.id, in: theme) : Color(role: .fgMuted, in: theme)
        let dark = StoreLook.dark(store.id, open: open, in: theme)
        let shape = UnevenRoundedRectangle(topLeadingRadius: Radius.ticket, topTrailingRadius: Radius.ticket)
        Button {
            model.visit(store)
        } label: {
            VStack(spacing: 0) {
                Rectangle().fill(dark).frame(height: Space.s)
                StoreSign(store: store)
                    .padding(.horizontal, Space.xs)
                    .padding(.top, Space.xs - Space.xxs / 2)
                ShopAwning(color: color)
                    .frame(height: ShopAwning.height(for: width))
                    .padding(.top, Space.xs - Space.xxs / 2)
                    .zIndex(1)
                front(color: color, dark: dark)
                // The step down to the street.
                Rectangle()
                    .fill(ShopPavement.kerb)
                    .frame(height: ShopPavement.kerbHeight)
            }
            .background(StoreLook.wall(store.id, open: open, in: theme))
            .clipShape(shape)
            .onGeometryChange(for: Double.self) {
                Double($0.size.width)
            } action: {
                width = $0
            }
            .contentShape(shape)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(open ? Text(copy: "进店", bundle: .module) : Text(copy: "还没开门", bundle: .module))
        .accessibilityIdentifier("street.store.\(store.id)")
    }

    /// The window and the door, or a closed store's shutter across both.
    @ViewBuilder
    private func front(color: Color, dark: Color) -> some View {
        Group {
            if store.isOpen {
                HStack(spacing: Space.s) {
                    window(color)
                    ShopDoor(color: dark)
                        .frame(width: door)
                        .overlay(alignment: .top) { news }
                }
            } else {
                // How far it is from opening is said once, on the button under the street.
                ShopShutter()
                    .accessibilityRepresentation { StoreCopy.opens(store) }
            }
        }
        .padding(.horizontal, Space.s)
        .padding(.vertical, Space.xs + Space.xxs / 2)
        .frame(maxWidth: .infinity, minHeight: wall.lowerBound, maxHeight: wall.upperBound)
    }

    /// The window: a white frame round the glass and the model on its plinth.
    private func window(_ color: Color) -> some View {
        ZStack(alignment: .bottom) {
            ShopGlass()
            WindowModel(store: store.id, color: color)
                .frame(width: figure.width, height: figure.height)
                .padding(.bottom, Space.xxs)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.thumbnail, style: .continuous))
        .padding(frame)
        .background(
            Color(role: .bgCanvas, in: theme), in: RoundedRectangle(cornerRadius: Radius.pick, style: .continuous)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// NEW hung on the door's glass like a shop's open sign, while the store has something the
    /// member hasn't seen.
    @ViewBuilder private var news: some View {
        if model.hasNews(store.id) {
            VStack(spacing: -Sizing.hairline) {
                DoorSignString()
                    .stroke(
                        Color(role: .bgInk, in: theme),
                        style: StrokeStyle(lineWidth: Sizing.selectionStroke, lineJoin: .round)
                    )
                    .frame(width: Space.l + Space.xxs / 2, height: Space.s)
                InkTag.new
            }
            .padding(.top, Space.s + Space.xxs)
        }
    }
}

/// The string NEW hangs from on the door: up to a nail and down again.
private struct DoorSignString: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }
    }
}

/// The street's map: every store's badge in street order, the centred one ringed, a closed one
/// faded, a dot where something new waits. A tap walks to that store.
private struct StreetMap: View {
    let model: StreetModel
    let current: String?
    let walk: (String) -> Void
    @Environment(\.sceneTheme) private var theme
    private let size: Double = 28

    var body: some View {
        HStack(spacing: Space.xs + Space.xxs / 2) {
            ForEach(model.catalog.stores) { store in
                let shape = RoundedRectangle(cornerRadius: Radius.thumbnail, style: .continuous)
                Button {
                    walk(store.id)
                } label: {
                    StoreBadge(store: store.id)
                        .padding(Space.xxs - 1)
                        .frame(width: size, height: size)
                        .background(Color(role: .bgCanvas, in: theme), in: shape)
                        .overlay {
                            shape.strokeBorder(
                                Color(role: store.id == current ? .bgBrand : .borderDefault, in: theme),
                                lineWidth: store.id == current ? 2 : Sizing.hairline)
                        }
                        .opacity(store.isOpen || store.id == current ? 1 : 0.38)
                        .overlay(alignment: .topTrailing) {
                            if store.isOpen && model.hasNews(store.id) {
                                Circle()
                                    .fill(Color(role: .bgBrand, in: theme))
                                    .frame(width: 10, height: 10)
                                    .overlay { Circle().strokeBorder(Color(role: .bgCanvas, in: theme), lineWidth: 2) }
                                    .offset(x: Space.xxs, y: -Space.xxs)
                            }
                        }
                        .frame(width: Sizing.minimumTapTarget, height: Sizing.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                .padding(.horizontal, -(Sizing.minimumTapTarget - size) / 2 + Space.xxs / 2)
                .accessibilityLabel(StoreCopy.name(store.id))
                .accessibilityAddTraits(store.id == current ? .isSelected : [])
                .accessibilityIdentifier("street.map.\(store.id)")
            }
        }
    }
}

/// A store's colours on the street, from its badge's art.
enum StoreLook {
    /// The awning's and the glass's colour; graphite for a badge drawn only in greys.
    static func color(_ store: String, in theme: SceneTheme) -> Color {
        PlaceholderCharacter.storeColor(store).map { Color($0) } ?? Color(role: .bgBrand, in: theme)
    }

    /// The name on the sign: white on the store's colour, or ink where that colour is too light
    /// for white to read (HALF MOON's mint).
    static func signInk(_ store: String, in theme: SceneTheme) -> Color {
        PlaceholderCharacter.storeColor(store).map(isLight) == true
            ? Color(role: .fgDefault, in: theme) : Color(role: .fgOnBrand, in: theme)
    }

    /// The cap and the door: the store's colour darkened (a light one more,
    /// so white reads on it); graphite for a badge without a colour, grey for a closed store.
    static func dark(_ store: String, open: Bool, in theme: SceneTheme) -> Color {
        guard open else { return Color(role: .fgMuted, in: theme) }
        guard let rgba = PlaceholderCharacter.storeColor(store) else { return Color(role: .bgBrand, in: theme) }
        return Color(mix(rgba, toward: 0, by: isLight(rgba) ? 0.45 : 0.3))
    }

    /// The wall: a pale tint of the store's colour; mist for a closed store or one without a
    /// colour.
    static func wall(_ store: String, open: Bool, in theme: SceneTheme) -> Color {
        guard open, let rgba = PlaceholderCharacter.storeColor(store) else { return Color(role: .bgSubtle, in: theme) }
        return Color(mix(rgba, toward: 255, by: 0.82))
    }

    /// `rgba` moved `amount` of the way to the grey `level` (0 black, 255 white).
    private static func mix(_ rgba: RGBAColor, toward level: UInt8, by amount: Double) -> RGBAColor {
        func channel(_ value: UInt8) -> UInt8 {
            UInt8((Double(value) + (Double(level) - Double(value)) * amount).rounded())
        }
        return RGBAColor(red: channel(rgba.red), green: channel(rgba.green), blue: channel(rgba.blue))
    }

    /// The colour of a limited store's tag, so each kind of limit wears its own (冬季限定 blue,
    /// 感恩节 orange, 圣诞 green): `names.json`'s (the uploaded file's, else the bundled one's),
    /// else nil for the limited colour.
    static func limited(_ store: String) -> RGBAColor? {
        PlaceholderCharacter.names().stores[store]?.limitedColor
    }

    private static func isLight(_ rgba: RGBAColor) -> Bool {
        0.299 * Double(rgba.red) + 0.587 * Double(rgba.green) + 0.114 * Double(rgba.blue) > 160
    }
}

/// A limited store's tag (冬季限定): its words in the limit's colour on a wash of the same
/// colour, the limited colour unless the limit names its own.
struct LimitedTag: View {
    let word: Text
    let color: RGBAColor?
    @Environment(\.sceneTheme) private var theme

    init?(store: String) {
        guard let word = StoreCopy.limited(store) else { return nil }
        (self.word, color) = (word, StoreLook.limited(store))
    }

    var body: some View {
        let ink = color.map { Color($0) } ?? Color(role: .fgLimited, in: theme)
        word
            .typeStyle(TypeRamp.label)
            .foregroundStyle(ink)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, Space.xs - Space.xxs / 2)
            .frame(height: CoachTag.Size.small.height)
            .background(ink.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.thumbnail, style: .continuous))
    }
}
#endif
