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
/// member claims it (领取) from a sheet; the 「已放进衣橱」 notice then offers to try it on. Boxes
/// that came in open from a pop-up over the page.
public struct ShoppingStreetPage: View {
    let model: StreetModel
    /// A store's rack is pushed and on screen over the street.
    @State private var rackOnScreen = false
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
                        .onAppear { rackOnScreen = true }
                        .onDisappear { rackOnScreen = false }
                }
            }
            .onAppear { model.didOpen() }
    }

    /// The store whose rack is pushed; the system's back leaves it.
    private var openStore: Binding<String?> {
        Binding(get: { model.store }, set: { if $0 == nil { model.leaveStore() } })
    }

    /// The street (`store` nil) or a store's rack. The pop-up, the 领取 sheet and the notice
    /// belong to whichever page is on screen on top, so the street under a rack doesn't show them
    /// twice, and the street shows them until the rack it opens on has slid in.
    private func page(_ store: EditorChoices.Store?) -> some View {
        let isOnTop = store != nil || !rackOnScreen
        return ScrollView {
            VStack(alignment: .leading, spacing: Space.xs) {
                if let store {
                    HStack(spacing: Space.xs) { RackHeader(model: model, store: store) }
                }
                // A 领取 that didn't save: the piece is back to NEW, so say why.
                if model.claimFailed {
                    Text(copy: "网络开小差了，没领上", bundle: .module)
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                        .accessibilityIdentifier("street.claimFailed")
                }
                if let store {
                    StoreRack(model: model, store: store)
                } else {
                    street
                }
            }
            .padding(.horizontal, Space.pageMargin)
            .padding(.bottom, Space.l)
        }
        .scrollIndicators(.hidden)
        .barTitleOnScroll(store.map { StoreCopy.name($0.id) } ?? Text(copy: "商店街", bundle: .module))
        .background(Color(role: .bgCanvas, in: theme))
        // The pop-up is modal: VoiceOver (and a UI test) reaches only it, not the rack under it.
        .accessibilityHidden(model.arrival != nil)
        .overlay {
            if isOnTop, let arrival = model.arrival {
                ArrivalPopup(model: model, arrival: arrival).transition(.opacity)
            }
        }
        .animation(.wildcard(Motion.sheet, reduceMotion: reduceMotion), value: model.arrival)
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
            onTap: { model.tryOn($0.id) },
            content: { claimed in ClaimedBanner(model: model, piece: claimed.id) }
        )
        // A container, so its identifier doesn't replace the pop-up's (editor.arrival) and the rest.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("street.page")
    }

    @ViewBuilder
    private var street: some View {
        Text(copy: "商店街", bundle: .module)
            .typeStyle(TypeRamp.taskTitle)
            .foregroundStyle(Color(role: .fgDefault, in: theme))
            .accessibilityAddTraits(.isHeader)
        StoreStreet(model: model)
            .padding(.top, Space.s)
    }
}

/// The open store's name, its Chinese name, its 冬季限定 tag if it is limited, and ⓘ, which opens 「练这些运动解锁」 where its pieces
/// have rules.
private struct RackHeader: View {
    let model: StreetModel
    let store: EditorChoices.Store
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        StoreCopy.name(store.id)
            .typeStyle(TypeRamp.scoreSmall)
            .foregroundStyle(Color(role: .fgDefault, in: theme))
            .lineLimit(1)
            .accessibilityAddTraits(.isHeader)
        StoreCopy.local(store.id)
            .typeStyle(TypeRamp.footnote)
            .foregroundStyle(Color(role: .fgMuted, in: theme))
            .lineLimit(1)
        if let limited = StoreCopy.limited(store.id) {
            limited
                .typeStyle(TypeRamp.label)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .lineLimit(1)
        }
        Spacer(minLength: 0)
        if let sports = model.sports(of: store.id) {
            Button {
                model.tip = store.id
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .frame(width: Sizing.compactControl, height: Sizing.compactControl)
                    .contentShape(Circle())
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

/// A store's copy, from the art's `names.json` (the uploaded one, else the one bundled): its name
/// (a wordmark, the same in every language), its Chinese name, its sports, its line, how a closed
/// one unlocks and the tag a limited one wears. Data only, so a store's words change by upload.
enum StoreCopy {
    static func name(_ store: String) -> Text { text(words(store)?.name, or: store) }
    static func local(_ store: String) -> Text { text(words(store)?.local, or: store) }
    static func sports(_ store: String) -> Text { text(words(store)?.sports, or: "") }
    static func tagline(_ store: String) -> Text { text(words(store)?.tagline, or: "") }
    static func unlock(_ store: String) -> Text { text(words(store)?.unlock, or: "") }
    /// How far a closed store is from opening: 「还有 2 次开门」 once the server says, else how it unlocks.
    static func opens(_ store: EditorChoices.Store) -> Text {
        guard let toGo = store.toGo else { return unlock(store.id) }
        return Text(copy: "还有 \(toGo) 次开门", bundle: .module)
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
