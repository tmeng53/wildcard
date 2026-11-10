#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import CharacterEditorDomain
import Contracts
import DesignSystem
import DesignSystemUI
import SportsUI
import SwiftUI

/// 商店街, its own page from 我: the stores side by side along a street (`StoreStreet`, approved
/// 2026-11-06); a store's rack is pushed over it, and the system's back button and swipe go back,
/// from a store to the street and from the street to 我. A piece that came in wears NEW until the
/// member claims it (领取) from a sheet; the 「已放进衣橱」 notice then offers to try it on.
public struct ShoppingStreetPage: View {
    let model: StreetModel
    /// The store in the middle of the street, whose 进店 is pinned at the bottom.
    @State private var centred: String?
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: StreetModel) {
        self.model = model
    }

    public var body: some View {
        page(nil)
            .pushedPage()
            .navigationDestination(item: openStore) { id in
                if let store = model.catalog.stores.first(where: { $0.id == id }) {
                    page(store)
                        .pushedPage()
                }
            }
            .onAppear { model.didOpen() }
    }

    /// The store whose rack is pushed; the system's back leaves it.
    private var openStore: Binding<String?> {
        Binding(get: { model.store }, set: { if $0 == nil { model.leaveStore() } })
    }

    /// The street (`store` nil) or a store's rack. The 领取 sheet and the notice
    /// belong to the page on top, which the model says (a store open is its rack), so exactly one
    /// page shows them. Telling it from the pages' appearing let both show them at once, as when
    /// 商店街 and a rack are pushed together from a notice or the editor covers the rack, and a
    /// tap could land on the copy under the rack.
    private func page(_ store: EditorChoices.Store?) -> some View {
        let isOnTop = (store == nil) == (model.store == nil)
        return content(store)
            // The street's 进店 stays at the bottom, above the tab bar, however tall the phone.
            .safeAreaInset(edge: .bottom) { if store == nil { counter } }
            .barTitleOnScroll(store.map { StoreCopy.name($0.id) } ?? Text(copy: "商店街", bundle: .module))
            // The street stands under a pale sky; a store's rack is a white page.
            .background(store == nil ? ShopPavement.sky : Color(role: .bgCanvas, in: theme))
            .sheet(
                item: Binding(
                    get: { isOnTop ? model.sheet.map(ClaimSheet.Piece.init) : nil }, set: { model.sheet = $0?.id })
            ) { piece in
                ClaimSheet(model: model, piece: piece.id)
                    .presentationDetents([.height(ClaimSheet.height)])
                    .presentationDragIndicator(.visible)
            }
            .noticeBanner(
                item: Binding(get: { isOnTop ? model.claimedNotice : nil }, set: { model.claimedNotice = $0 }),
                hold: { [noticeHold = model.noticeHold] _ in noticeHold ?? Motion.noticeHold },
                onTap: { model.tryOn($0.id) },
                content: { claimed in ClaimedBanner(model: model, piece: claimed.id) }
            )
            // A container, so its identifier doesn't replace its pieces' own.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("street.page")
    }

    @ViewBuilder
    private var counter: some View {
        let stores = model.catalog.stores
        if let shown = stores.first(where: { $0.id == centred }) ?? stores.first {
            StreetCounter(model: model, store: shown) { id in
                withAnimation(.wildcard(Motion.page, reduceMotion: reduceMotion)) { centred = id }
            }
            // A white sheet with round top corners laid over the street, opaque, so the street
            // scrolling under it on a short phone doesn't show through; the street's stones fill
            // its corners.
            .background {
                UnevenRoundedRectangle(topLeadingRadius: Radius.menu, topTrailingRadius: Radius.menu)
                    .fill(Color(role: .bgCanvas, in: theme))
                    .ignoresSafeArea(edges: .bottom)
            }
            .background(alignment: .top) { ShopPavement.stone.frame(height: Radius.menu) }
        }
    }

    /// A store's rack scrolls. The street fills the page between the bar and its pinned 进店, its
    /// storefronts' windows taking whatever height the phone has, and scrolls only where even its
    /// smallest windows don't fit.
    @ViewBuilder
    private func content(_ store: EditorChoices.Store?) -> some View {
        if let store {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s) {
                    RackHeader(model: model, store: store)
                    claimFailed
                    StoreRack(model: model, store: store)
                }
                .padding(.horizontal, Space.pageMargin)
                .padding(.bottom, Space.l)
            }
            .scrollIndicators(.hidden)
        } else {
            // The page's height between the bar and 进店, which the street is given whole; on a
            // phone too short for it the street keeps its smallest size and scrolls.
            GeometryReader { page in
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        claimFailed
                        StoreStreet(model: model, current: $centred)
                            .padding(.top, Space.xl)
                    }
                    .padding(.horizontal, Space.pageMargin)
                    .frame(minHeight: page.size.height, idealHeight: page.size.height, alignment: .top)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
            }
        }
    }

    /// A 领取 that didn't save: the piece is back to NEW, so say why.
    @ViewBuilder
    private var claimFailed: some View {
        if model.claimFailed {
            Text(copy: "网络开小差了，没领上", bundle: .module)
                .typeStyle(TypeRamp.footnote)
                .foregroundStyle(Color(role: .fgMuted, in: theme))
                .accessibilityIdentifier("street.claimFailed")
        }
    }
}

/// The open store's logo (its badge and name, with its 冬季限定 tag if it is limited), ⓘ, which
/// opens 「练这些运动解锁」 where its pieces have rules, and its slogan under them (approved
/// 2026-11-08).
private struct RackHeader: View {
    let model: StreetModel
    let store: EditorChoices.Store
    @Environment(\.sceneTheme) private var theme
    private let badge: Double = 52

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.s) {
                StoreBadge(store: store.id)
                    .frame(width: badge, height: badge)
                StoreCopy.name(store.id)
                    .typeStyle(TypeRamp.scoreCard)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityAddTraits(.isHeader)
                if let tag = LimitedTag(store: store.id) { tag }
                Spacer(minLength: 0)
                info
            }
            StoreCopy.tagline(store.id)
                .typeStyle(TypeRamp.footnote)
                .foregroundStyle(Color(role: .fgMuted, in: theme))
        }
    }

    @ViewBuilder private var info: some View {
        if let sports = model.sports(of: store.id) {
            Button {
                model.tip = store.id
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .frame(width: Sizing.compactControl, height: Sizing.compactControl)
                    // Drawn small, tapped at the full 44 points.
                    .contentShape(Rectangle().inset(by: -(Sizing.minimumTapTarget - Sizing.compactControl) / 2))
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(Text(copy: "练这些运动解锁", bundle: .module))
            .accessibilityIdentifier("street.rack.info")
            .popover(isPresented: tipShown) {
                SportsTip(sports: sports).presentationCompactAdaptation(.popover)
            }
        }
    }

    private var tipShown: Binding<Bool> {
        Binding(get: { model.tip == store.id }, set: { if !$0 { model.tip = nil } })
    }
}

/// A store's badge, from the bundled art.
struct StoreBadge: View {
    let store: String

    var body: some View {
        if let artwork = try? PlaceholderCharacter.storeBadge(store) {
            ArtworkView(artwork)
                .accessibilityHidden(true)
        }
    }
}

/// A store's words, from `names.json` (`AvatarArt`'s `ArtNames`: the bundled file with the
/// uploaded one in front), so a store is named and renamed as data: its name (a wordmark, the
/// same in every language), its name in the reader's language, its sports, its line, how a
/// closed one unlocks and its limited tag.
enum StoreCopy {
    static func name(_ store: String) -> Text { text(words(store)?.name, or: store) }
    static func local(_ store: String) -> Text { text(words(store)?.local, or: store) }
    /// Its sports line as one word a sport, for the street's pills: split at commas where the
    /// language lists with them (English), at spaces in Chinese.
    static func sports(_ store: String) -> [String] {
        let line = words(store)?.sports?.localized ?? ""
        let commas = CharacterSet(charactersIn: ",，")
        // A Latin line without commas is one phrase (Any sport, Winter sports); Chinese
        // lists its sports with spaces.
        let latin = line.unicodeScalars.contains { $0.isASCII && CharacterSet.letters.contains($0) }
        let separators: CharacterSet =
            line.unicodeScalars.contains(where: commas.contains) ? commas : latin ? CharacterSet() : .whitespaces
        return line.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
    }
    static func tagline(_ store: String) -> Text { text(words(store)?.tagline, or: "") }
    static func unlock(_ store: String) -> Text { text(words(store)?.unlock, or: "") }
    /// How far a closed store is from opening: 「还有 2 天开门」 once the server says, else how it unlocks.
    static func opens(_ store: EditorChoices.Store) -> Text {
        guard let toGo = store.toGo else { return unlock(store.id) }
        return Text(copy: "还有 \(toGo) 天开门", bundle: .module)
    }
    /// The tag a limited store wears, such as 冬季限定; nil for one without.
    static func limited(_ store: String) -> Text? {
        words(store)?.limited.map { Text(verbatim: $0.localized) }
    }

    private static func words(_ store: String) -> ArtNames.Store? { PlaceholderCharacter.names().stores[store] }

    private static func text(_ words: CatalogNames?, or fallback: String) -> Text {
        Text(verbatim: words?.localized ?? fallback)
    }
}
#endif
