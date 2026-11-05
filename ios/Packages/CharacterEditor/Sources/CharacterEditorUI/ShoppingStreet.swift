#if canImport(SwiftUI)
import AvatarArt
import AvatarDomain
import AvatarUI
import CharacterEditorDomain
import Contracts
import DesignSystem
import DesignSystemUI
import SportsUI
import SwiftUI

/// 商店街, its own page from 我 (approved 2026-11-04): each store a card, WARM-UP across the top
/// and the rest two a row, greyed while closed; then the open store's rack. A piece that came in
/// wears NEW until the member claims it (领取) from a sheet; the 「已放进衣橱」 notice then offers to
/// try it on. Boxes that came in open from a pop-up over the page.
public struct ShoppingStreetPage: View {
    let model: StreetModel
    let back: () -> Void
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: StreetModel, back: @escaping () -> Void) {
        (self.model, self.back) = (model, back)
    }

    public var body: some View {
        @Bindable var model = model
        let store = model.store.flatMap { id in model.catalog.stores.first(where: { $0.id == id }) }
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.xs) {
                HeaderButton(Text("返回", bundle: .module), systemImage: "chevron.left") {
                    if store != nil { model.leaveStore() } else { back() }
                }
                .accessibilityIdentifier("street.back")
                if let store { RackHeader(model: model, store: store) }
            }
            .padding(.horizontal, Space.pageMargin)
            .padding(.vertical, Space.xs)
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xs) {
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
        }
        .background(Color(role: .bgCanvas, in: theme))
        .swipesBack { if store != nil { model.leaveStore() } else { back() } }
        .overlay {
            if let arrival = model.arrival {
                ArrivalPopup(model: model, arrival: arrival).transition(.opacity)
            }
        }
        .animation(.wildcard(Motion.sheet, reduceMotion: reduceMotion), value: model.arrival)
        .animation(.wildcard(Motion.page, reduceMotion: reduceMotion), value: model.store)
        .sheet(item: Binding(get: { model.sheet.map(ClaimSheet.Piece.init) }, set: { model.sheet = $0?.id })) { piece in
            ClaimSheet(model: model, piece: piece.id)
                .presentationDetents([.height(ClaimSheet.height)])
                .presentationDragIndicator(.visible)
        }
        .noticeBanner(
            item: $model.claimedNotice, onTap: { model.tryOn($0.id) },
            content: { claimed in ClaimedBanner(model: model, piece: claimed.id) }
        )
        .onAppear { model.didOpen() }
        .accessibilityIdentifier("street.page")
    }

    @ViewBuilder
    private var street: some View {
        let stores = model.catalog.stores
        Text("商店街", bundle: .module)
            .typeStyle(TypeRamp.taskTitle)
            .foregroundStyle(Color(role: .fgDefault, in: theme))
            .accessibilityAddTraits(.isHeader)
        Text("进店挑衣服。", bundle: .module)
            .typeStyle(TypeRamp.footnote)
            .foregroundStyle(Color(role: .fgMuted, in: theme))
        // The open stores across the top, the rest two a row.
        let open = stores.filter(\.isOpen)
        let closed = stores.filter { !$0.isOpen }
        VStack(spacing: Space.xs) {
            ForEach(open) { StoreCard(model: model, store: $0) }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.xs), count: 2), spacing: Space.xs)
            {
                ForEach(closed) { StoreCard(model: model, store: $0) }
            }
        }
        .padding(.top, Space.s)
    }
}

/// A store on the street. An open one is white with a hairline, its badge, name (NEW beside it
/// while a piece waits there), Chinese name and the sports that open its pieces, and says 营业中; a
/// closed one is grey, a lock in place of its badge, its name faded, and says how it unlocks.
private struct StoreCard: View {
    let model: StreetModel
    let store: EditorChoices.Store
    @Environment(\.sceneTheme) private var theme
    private let badge: Double = 30

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        Button {
            model.visit(store)
        } label: {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Group {
                    if store.isOpen {
                        StoreBadge(store: store.id)
                    } else {
                        Image(systemName: "lock")
                            .font(.system(size: badge / 2))
                            .foregroundStyle(Color(role: .fgMuted, in: theme))
                            .accessibilityHidden(true)
                    }
                }
                .frame(width: badge, height: badge)
                HStack(spacing: Space.xs) {
                    StoreCopy.name(store.id)
                        .typeStyle(TypeRamp.scoreSmall)
                        .foregroundStyle(Color(role: .fgDefault, in: theme))
                        .opacity(store.isOpen ? 1 : 0.45)
                        .lineLimit(1)
                    if store.isOpen && model.hasNews(store.id) {
                        InkTag.new.accessibilityIdentifier("street.store.\(store.id).new")
                    }
                }
                if store.isOpen {
                    Text("\(StoreCopy.local(store.id)) · \(sportsLine)", bundle: .module)
                        .typeStyle(TypeRamp.caption)
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    StoreCopy.unlock(store.id)
                        .typeStyle(TypeRamp.label)
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.s)
            .background(Color(role: store.isOpen ? .bgCanvas : .bgSubtle, in: theme), in: shape)
            .overlay {
                if store.isOpen {
                    shape.strokeBorder(Color(role: .borderDefault, in: theme), lineWidth: Sizing.selectionStroke)
                }
            }
            .overlay(alignment: .topTrailing) {
                // A limited store says so, never its dates.
                if store.isOpen, let limited = StoreCopy.limited(store.id) {
                    limited
                        .typeStyle(TypeRamp.label)
                        .foregroundStyle(Color(role: .fgDefault, in: theme))
                        .padding(Space.s)
                } else if store.isOpen {
                    Text("营业中", bundle: .module)
                        .typeStyle(TypeRamp.label)
                        .foregroundStyle(Color(role: .fgPositive, in: theme))
                        .padding(Space.s)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(store.isOpen ? Text("进店", bundle: .module) : Text("还没开门", bundle: .module))
        .accessibilityIdentifier("street.store.\(store.id)")
    }

    /// The sports its pieces' rules count, as its tip lists them, or its own line where none has one.
    private var sportsLine: Text {
        guard let sports = model.sports(of: store.id) else { return StoreCopy.sports(store.id) }
        guard !sports.isEmpty else { return Text("练什么都算", bundle: .module) }
        return Text(verbatim: sports.map(\.localizedName).joined(separator: " "))
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
    static func sports(_ store: String) -> Text { text(uploaded(store)?.sports, sportLines[store], or: "") }
    static func tagline(_ store: String) -> Text { text(uploaded(store)?.tagline, taglines[store], or: "") }
    static func unlock(_ store: String) -> Text { text(uploaded(store)?.unlock, unlocks[store], or: "") }
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
}
#endif
