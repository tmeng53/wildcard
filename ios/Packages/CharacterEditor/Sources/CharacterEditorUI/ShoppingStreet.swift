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

    /// The street (`store` nil) or a store's rack. The pop-up, the 领取 sheet and the notice
    /// belong to the page on top, which the model says (a store open is its rack), so exactly one
    /// page shows them. Telling it from the pages' appearing let both show them at once, as when
    /// 商店街 and a rack are pushed together from a notice or the editor covers the rack, and a
    /// tap could land on the copy under the rack.
    private func page(_ store: EditorChoices.Store?) -> some View {
        let isOnTop = (store == nil) == (model.store == nil)
        return ScrollView {
            VStack(alignment: .leading, spacing: Space.xs) {
                if let store {
                    HStack(spacing: Space.xs) { RackHeader(model: model, store: store) }
                }
                // A 领取 that didn't save: the piece is back to NEW, so say why.
                if model.claimFailed {
                    Text("网络开小差了，没领上", bundle: .module)
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
        // The street's 进店 stays at the bottom, above the tab bar, however tall the phone.
        .safeAreaInset(edge: .bottom) { if store == nil { counter } }
        .barTitleOnScroll(store.map { StoreCopy.name($0.id) } ?? Text("商店街", bundle: .module))
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
            hold: { [noticeHold = model.noticeHold] _ in noticeHold ?? Motion.noticeHold },
            onTap: { model.tryOn($0.id) },
            content: { claimed in ClaimedBanner(model: model, piece: claimed.id) }
        )
        // A container, so its identifier doesn't replace the pop-up's (editor.arrival) and the rest.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("street.page")
    }

    @ViewBuilder
    private var counter: some View {
        let stores = model.catalog.stores
        if let shown = stores.first(where: { $0.id == centred }) ?? stores.first {
            StreetCounter(model: model, store: shown)
                // Opaque, so the street scrolling under it on a short phone doesn't show through.
                .background(Color(role: .bgCanvas, in: theme))
        }
    }

    private var street: some View {
        StoreStreet(model: model, current: $centred)
            .padding(.top, Space.xl)
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
        if let tag = LimitedTag(store: store.id) { tag }
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
            .accessibilityLabel(Text("练这些运动解锁", bundle: .module))
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

/// A store's copy, from the String Catalog: its name (a wordmark, the same in every language),
/// its Chinese name, its sports, its line, and how a closed one unlocks.
enum StoreCopy {
    static func name(_ store: String) -> Text { text(uploaded(store)?.name, names[store], or: store) }
    static func local(_ store: String) -> Text { text(uploaded(store)?.local, locals[store], or: store) }
    /// Its sports line as one word a sport, for the street's pills: split at commas where the
    /// language lists with them (English), at spaces in Chinese.
    static func sports(_ store: String) -> [String] {
        let line =
            uploaded(store)?.sports?.localized
            ?? sportLines[store].map { Bundle.module.inAppLanguage.localizedString(forKey: $0, value: nil, table: nil) }
            ?? ""
        let commas = CharacterSet(charactersIn: ",，")
        // A Latin line without commas is one phrase (Any sport counts, Winter sports); Chinese
        // lists its sports with spaces.
        let latin = line.unicodeScalars.contains { $0.isASCII && CharacterSet.letters.contains($0) }
        let separators: CharacterSet =
            line.unicodeScalars.contains(where: commas.contains) ? commas : latin ? CharacterSet() : .whitespaces
        return line.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
    }
    static func tagline(_ store: String) -> Text { text(uploaded(store)?.tagline, taglines[store], or: "") }
    static func unlock(_ store: String) -> Text { text(uploaded(store)?.unlock, unlocks[store], or: "") }
    /// How far a closed store is from opening: 「还有 2 次开门」 once the server says, else how it unlocks.
    static func opens(_ store: EditorChoices.Store) -> Text {
        guard let toGo = store.toGo else { return unlock(store.id) }
        return Text("还有 \(toGo) 次开门", bundle: .module)
    }
    /// The tag a limited store wears, such as 冬季限定; nil for one without.
    static func limited(_ store: String) -> Text? {
        if let words = uploaded(store)?.limited { return Text(verbatim: words.localized) }
        return limits[store].map { text(nil, $0, or: "") }
    }

    /// A store added by upload carries its words in `names.json`, in front of the catalog's.
    private static func uploaded(_ store: String) -> ArtNames.Store? { PlaceholderCharacter.names().stores[store] }

    private static func text(_ words: CatalogNames?, _ key: String?, or fallback: String) -> Text {
        if let words { return Text(verbatim: words.localized) }
        guard let key else { return Text(verbatim: fallback) }
        return Text(LocalizedStringKey(key), bundle: .module)
    }

    private static let names = [
        "warmup": "WARM-UP", "lap": "LAP NINE", "nolook": "NO LOOK", "moss": "MOSSWAY", "halfmoon": "HALF MOON",
        "deuce": "DEUCE CLUB", "powder": "POWDER DAY",
    ]
    private static let locals = [
        "warmup": "热身社", "lap": "第九圈", "nolook": "不看传球", "moss": "苔径", "halfmoon": "半月", "deuce": "平分俱乐部",
        "powder": "粉雪日",
    ]
    private static let sportLines = [
        "warmup": "走路 跑步 力量训练", "lap": "跑步 走路", "nolook": "篮球 排球", "moss": "徒步 越野跑 攀岩",
        "halfmoon": "练什么都算", "deuce": "网球 匹克球 壁球", "powder": "冬季运动",
    ]
    private static let taglines = [
        "warmup": "先热身，再上场。", "lap": "操场第九圈，才是今天真正开始的地方。", "nolook": "眼睛看左边，球已经到右边了。",
        "moss": "路不在地图上，在苔藓上。", "halfmoon": "做完半月式，再去喝一杯燕麦拿铁。", "deuce": "平分之后，才是真的比赛。",
        "powder": "雪道见，压个弯。",
    ]
    private static let unlocks = [
        "lap": "跑步 3 次解锁", "nolook": "篮球 3 次解锁", "moss": "攀岩或徒步 3 次解锁", "halfmoon": "随便练 3 次解锁",
        "deuce": "网球类 3 次解锁",
    ]
    private static let limits = ["powder": "冬季限定"]
    /// Each bundled limit's tag colour (冬季限定: glacier blue); an uploaded store names its own
    /// in `names.json`.
    static let limitColors = ["powder": RGBAColor(red: 0x1E, green: 0x6A, blue: 0x9E)]
}
#endif
