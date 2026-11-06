#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import CharacterEditorDomain
import DesignSystem
import DesignSystemUI
import SportsUI
import SwiftUI

/// 商店街 as a street (逛街版, approved 2026-11-06): the stores side by side, one storefront at a
/// time in the middle with its neighbours peeking in, paged by the system's scroll. The member
/// stands on the sidewalk under it. Under the sidewalk, the street's map (every store's badge, a
/// dot where something new waits, a tap walks there), the centred store's sports and its button:
/// 进店 when open, how it unlocks when not.
struct StoreStreet: View {
    let model: StreetModel
    @State private var current: String?
    /// The street is sliding, by a swipe or a tap on its map: the member strolls.
    @State private var walking = false
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How much of each neighbour peeks in at the screen's edges.
    private let peek: Double = 48
    private let character = CGSize(width: 100, height: 134)
    private let sidewalk: Double = 140

    var body: some View {
        let stores = model.catalog.stores
        let shown = stores.first { $0.id == current } ?? stores.first
        VStack(spacing: Space.m) {
            ZStack(alignment: .bottom) {
                Rectangle()
                    .fill(Color(role: .bgSubtle, in: theme))
                    .frame(height: sidewalk)
                    .overlay(alignment: .top) {
                        Rectangle().fill(Color(role: .borderDefault, in: theme)).frame(height: Space.xxs)
                    }
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
                .padding(.bottom, sidewalk - Space.m)
                walker
            }
            StreetMap(model: model, current: shown?.id) { id in
                withAnimation(.wildcard(Motion.page, reduceMotion: reduceMotion)) { current = id }
            }
            if let shown { counter(for: shown) }
        }
        // The street runs to the screen's edges, past the page's margins.
        .padding(.horizontal, -Space.pageMargin)
    }

    /// The member with their shopping bags on the sidewalk under the store in the middle,
    /// strolling while the street slides and, once it stops, spotting something in the window.
    private var walker: some View {
        ShopperView(look: model.draft.outfit, persona: model.draft.persona, walking: walking && !reduceMotion)
            .frame(width: character.width, height: character.height)
            .padding(.bottom, Space.xxs)
    }

    /// The centred store's sports and its button.
    @ViewBuilder
    private func counter(for store: EditorChoices.Store) -> some View {
        VStack(spacing: Space.m) {
            sports(store.id)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("street.sports")
            if store.isOpen {
                Button {
                    model.visit(store)
                } label: {
                    Text("进店", bundle: .module).frame(maxWidth: .infinity)
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
    }

    /// The sports its pieces' rules count as pills, as its tip lists them, or its own line where
    /// none has one.
    @ViewBuilder
    private func sports(_ store: String) -> some View {
        if let sports = model.sports(of: store) {
            FlowRow(spacing: Space.xs, centred: true) {
                if sports.isEmpty {
                    SportPill(word: Text("练什么都算", bundle: .module))
                } else {
                    ForEach(sports, id: \.self) { SportPill(word: $0.name) }
                }
            }
        } else {
            StoreCopy.sports(store)
                .typeStyle(TypeRamp.footnote)
                .foregroundStyle(Color(role: .fgMuted, in: theme))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

}

/// One store's front: a graphite cap and its striped awning in the store's colour, then the wall
/// with its window (the store's badge, name, Chinese name and line on the glass, 冬季限定 in the
/// corner) and a glass door. A store with something new hangs NEW from its awning; a closed one
/// has its shutter down, saying how it unlocks. A tap on an open one walks in.
private struct Storefront: View {
    let model: StreetModel
    let store: EditorChoices.Store
    @Environment(\.sceneTheme) private var theme

    private let awning: Double = 34
    private let window: Double = 220
    private let frame: Double = 6
    private let door = CGSize(width: 50, height: 176)
    private let badge: Double = 48

    var body: some View {
        let color = StoreLook.color(store.id, in: theme)
        Button {
            model.visit(store)
        } label: {
            VStack(spacing: 0) {
                UnevenRoundedRectangle(topLeadingRadius: Radius.pick, topTrailingRadius: Radius.pick)
                    .fill(Color(role: store.isOpen ? .bgBrand : .fgMuted, in: theme))
                    .frame(height: Space.xs + Space.xxs / 2)
                Awning(color: color)
                    .frame(height: awning)
                    .zIndex(1)
                wall(color)
                    .padding(.top, -Space.xs)
            }
            .overlay(alignment: .topLeading) {
                if store.isOpen && model.hasNews(store.id) {
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(Color(role: .bgBrand, in: theme))
                            .frame(width: Sizing.selectionStroke, height: Space.s)
                        InkTag.new
                    }
                    .padding(.leading, Space.l)
                    .padding(.top, Space.xs + Space.xxs / 2 + awning)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(store.isOpen ? Text("进店", bundle: .module) : Text("还没开门", bundle: .module))
        .accessibilityIdentifier("street.store.\(store.id)")
    }

    private func wall(_ color: Color) -> some View {
        HStack(alignment: .bottom, spacing: Space.s) {
            glass(color)
            DoorView(height: door.height, width: door.width)
        }
        .padding(.horizontal, Space.s + Space.xxs / 2)
        .padding(.top, Space.m)
        .frame(maxWidth: .infinity)
        .background(Color(role: .bgSubtle, in: theme).overlay(color.opacity(0.06)))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(role: .bgBrand, in: theme))
                .overlay(color.opacity(0.3))
                .frame(height: frame)
        }
        .overlay {
            if !store.isOpen {
                Shutter(store: store)
                    .padding(.horizontal, Space.s + Space.xxs / 2)
                    .padding(.top, Space.m)
                    .padding(.bottom, frame)
            }
        }
    }

    /// The window: a graphite frame, glass with a hint of the store's colour and two glints, and
    /// the store's lockup on it.
    private func glass(_ color: Color) -> some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: Radius.pick, topTrailingRadius: Radius.pick)
        return ZStack {
            Color(role: .bgCanvas, in: theme).overlay(color.opacity(0.06))
            Glints()
            VStack(spacing: Space.xxs) {
                StoreBadge(store: store.id)
                    .padding(Space.xs - Space.xxs / 2)
                    .frame(width: badge, height: badge)
                    .background(
                        Color(role: .bgCanvas, in: theme),
                        in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    )
                    .padding(.bottom, Space.xs)
                StoreCopy.name(store.id)
                    .typeStyle(TypeRamp.scoreInline)
                    .foregroundStyle(StoreLook.wordmark(store.id, in: theme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                StoreCopy.local(store.id)
                    .typeStyle(TypeRamp.caption)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .lineLimit(1)
                StoreCopy.tagline(store.id)
                    .typeStyle(TypeRamp.footnoteEmphasis)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.top, Space.s)
            }
            .padding(.horizontal, Space.s)
            .opacity(store.isOpen ? 1 : 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: window)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(Color(role: store.isOpen ? .bgBrand : .fgMuted, in: theme), lineWidth: frame)
                .padding(.bottom, -frame)
                .clipShape(shape)
        }
        .overlay(alignment: .topTrailing) {
            // A limited store says so, never its dates.
            if store.isOpen, let tag = LimitedTag(store: store.id) {
                tag.padding(Space.s)
            }
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

    /// The name on the glass in the store's colour, or ink where that colour is too light to read
    /// on white (HALF MOON's mint).
    static func wordmark(_ store: String, in theme: SceneTheme) -> Color {
        guard let rgba = PlaceholderCharacter.storeColor(store) else { return Color(role: .fgDefault, in: theme) }
        return isLight(rgba) ? Color(role: .fgDefault, in: theme) : Color(rgba)
    }

    /// The colour of a limited store's tag, so each kind of limit wears its own (冬季限定 ice
    /// blue, 感恩节 orange, 圣诞 green): `names.json`'s, else the bundled one's, else nil for the
    /// limited colour.
    static func limited(_ store: String) -> RGBAColor? {
        PlaceholderCharacter.names().stores[store]?.limitedColor ?? StoreCopy.limitColors[store]
    }

    static func isLight(_ rgba: RGBAColor) -> Bool {
        0.299 * Double(rgba.red) + 0.587 * Double(rgba.green) + 0.114 * Double(rgba.blue) > 160
    }
}

/// A limited store's tag (冬季限定), in the limited colour, or the colour `names.json` gives its
/// limit, with ink words where that colour is too light for white.
struct LimitedTag: View {
    let word: Text
    let color: RGBAColor?
    @Environment(\.sceneTheme) private var theme

    init?(store: String) {
        guard let word = StoreCopy.limited(store) else { return nil }
        (self.word, color) = (word, StoreLook.limited(store))
    }

    var body: some View {
        let light = color.map(StoreLook.isLight) ?? false
        word
            .typeStyle(TypeRamp.label)
            .foregroundStyle(Color(role: light ? .fgDefault : .fgOnLimited, in: theme))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, Space.xs - Space.xxs / 2)
            .frame(height: CoachTag.Size.small.height)
            .background(
                color.map { Color($0) } ?? Color(role: .bgLimited, in: theme),
                in: RoundedRectangle(cornerRadius: Radius.thumbnail, style: .continuous))
    }
}
#endif
