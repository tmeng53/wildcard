#if canImport(SwiftUI)
import AvatarArt
import AvatarDomain
import AvatarUI
import CharacterEditorDomain
import DesignSystem
import DesignSystemUI
import SwiftUI

/// 穿搭: the shopping street, where each store is a card, then the open store's rack. WARM-UP
/// 热身社 runs the width of the street at the top; the other stores stand two a row, greyed
/// while closed, and a tap on one says how it opens. In a store, the colors of the piece just
/// picked stay put above the rack while it scrolls, as the skin swatches do on 长相.
struct ShoppingStreet: View {
    let model: CharacterEditorModel
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        let store = model.store.flatMap { id in model.draft.catalog.stores.first(where: { $0.id == id }) }
        VStack(alignment: .leading, spacing: 0) {
            if store != nil, let slot = model.picked {
                SwatchRow(model: model, slot: slot, named: true)
                    .padding(.horizontal, Space.pageMargin)
                    .padding(.top, Space.s)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xs) {
                    if let store {
                        StoreRack(model: model, store: store)
                    } else {
                        street
                    }
                }
                .padding(.horizontal, Space.pageMargin)
                .padding(.vertical, Space.s)
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private var street: some View {
        let stores = model.draft.catalog.stores
        Text("商店街", bundle: .module)
            .typeStyle(TypeRamp.headline)
            .foregroundStyle(Color(role: .fgDefault, in: theme))
            .accessibilityAddTraits(.isHeader)
        Text("进店挑衣服。灰色的店还没开门，点一下看怎么开。", bundle: .module)
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
        .padding(.top, Space.xxs)
        if let knocked = model.knocked {
            StoreCopy.opens(knocked)
                .typeStyle(TypeRamp.footnote)
                .foregroundStyle(Color(role: .fgMuted, in: theme))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Space.s)
                .padding(.vertical, Space.xs)
                .background(Color(role: .bgSubtle, in: theme), in: RoundedRectangle(cornerRadius: Radius.pick))
                .accessibilityIdentifier("editor.store.closed")
        }
    }
}

/// A store on the street: its badge, name, Chinese name and sports. An open one is white with a
/// hairline and says 营业中; a closed one is grey with a faded badge and name.
private struct StoreCard: View {
    let model: CharacterEditorModel
    let store: EditorChoices.Store
    @Environment(\.sceneTheme) private var theme
    private let badge: Double = 30

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        Button {
            model.visit(store)
        } label: {
            VStack(alignment: .leading, spacing: Space.xxs) {
                StoreBadge(store: store.id)
                    .frame(width: badge, height: badge)
                    .opacity(store.isOpen ? 1 : 0.45)
                StoreCopy.name(store.id)
                    .typeStyle(TypeRamp.scoreSmall)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .opacity(store.isOpen ? 1 : 0.45)
                    .lineLimit(1)
                Text("\(StoreCopy.local(store.id)) · \(StoreCopy.sports(store.id))", bundle: .module)
                    .typeStyle(TypeRamp.caption)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .fixedSize(horizontal: false, vertical: true)
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
                if store.isOpen {
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
        .accessibilityIdentifier("editor.store.\(store.id)")
    }
}

/// A store's badge, from the bundled art.
private struct StoreBadge: View {
    let store: String

    var body: some View {
        if let artwork = try? PlaceholderCharacter.storeBadge(store) {
            ArtworkView(artwork)
                .accessibilityHidden(true)
        }
    }
}

/// Inside a store: a way back to the street, the store's name and line, and its rack, three a
/// row, each piece with its name. The colors of the piece just picked sit above it, pinned.
private struct StoreRack: View {
    let model: CharacterEditorModel
    let store: EditorChoices.Store
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        HStack(spacing: Space.xs) {
            Button(action: model.leaveStore) {
                Label {
                    Text("商店街", bundle: .module)
                } icon: {
                    Image(systemName: "arrow.left")
                }
                .typeStyle(TypeRamp.footnoteEmphasis)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .padding(.horizontal, Space.s)
                .frame(minHeight: Sizing.compactControl)
                .background(Color(role: .bgSubtle, in: theme), in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityIdentifier("editor.store.back")
            StoreCopy.name(store.id)
                .typeStyle(TypeRamp.scoreSmall)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            StoreCopy.local(store.id)
                .typeStyle(TypeRamp.footnote)
                .foregroundStyle(Color(role: .fgMuted, in: theme))
                .lineLimit(1)
        }
        StoreCopy.tagline(store.id)
            .typeStyle(TypeRamp.footnote)
            .foregroundStyle(Color(role: .fgMuted, in: theme))
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.xs), count: 3), spacing: Space.xs) {
            ForEach(model.draft.catalog.rack(of: store.id), id: \.variant) { piece in
                RackPiece(model: model, slot: piece.slot, variant: piece.variant)
            }
        }
        .padding(.top, Space.xxs)
    }
}

/// One piece on a rack: its picture on its own, as a shop shows it, over its name.
private struct RackPiece: View {
    let model: CharacterEditorModel
    let slot: Slot
    let variant: String
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        VStack(spacing: Space.xxs) {
            PickTile(
                EditorNames.variant(variant, in: slot),
                isSelected: model.draft.picks.variants[slot] == variant,
                action: { model.pickFromRack(variant, for: slot) },
                picture: {
                    Thumbnail(outfit: preview, only: slot, crop: ThumbnailCrop.of(slot), cache: model.thumbnails)
                        .padding(Space.xs)
                }
            )
            .accessibilityIdentifier("editor.tile.\(slot.rawValue).\(variant)")
            EditorNames.variant(variant, in: slot)
                .typeStyle(TypeRamp.caption)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityHidden(true)
        }
    }

    /// The draft wearing the piece, so the piece shows in the colors it would be worn in.
    private var preview: Outfit {
        var draft = model.draft
        draft.pick(variant, for: slot)
        return draft.outfit
    }
}

/// A store's copy, from the String Catalog: its name (a wordmark, the same in every language),
/// its Chinese name, its sports, its line, and how it opens.
enum StoreCopy {
    static func name(_ store: String) -> Text { text(names[store], or: store) }
    static func local(_ store: String) -> Text { text(locals[store], or: store) }
    static func sports(_ store: String) -> Text { text(sportLines[store], or: "") }
    static func tagline(_ store: String) -> Text { text(taglines[store], or: "") }
    static func opens(_ store: String) -> Text { text(openings[store], or: "") }

    private static func text(_ key: String?, or fallback: String) -> Text {
        guard let key else { return Text(verbatim: fallback) }
        return Text(LocalizedStringKey(key), bundle: .module)
    }

    private static let names = [
        "warmup": "WARM-UP", "lap": "LAP NINE", "nolook": "NO LOOK", "moss": "MOSSWAY", "halfmoon": "HALF MOON",
        "deuce": "DEUCE CLUB",
    ]
    private static let locals = [
        "warmup": "热身社", "lap": "第九圈", "nolook": "不看传球", "moss": "苔径", "halfmoon": "半月", "deuce": "平分俱乐部",
    ]
    private static let sportLines = [
        "warmup": "走路 跑步 力量训练", "lap": "跑步 走路", "nolook": "篮球 排球", "moss": "徒步 越野跑 攀岩",
        "halfmoon": "练什么都算", "deuce": "网球 匹克球 壁球",
    ]
    private static let taglines = [
        "warmup": "先热身，再上场。", "lap": "操场第九圈，才是今天真正开始的地方。", "nolook": "眼睛看左边，球已经到右边了。",
        "moss": "路不在地图上，在苔藓上。", "halfmoon": "做完半月式，再去喝一杯燕麦拿铁。", "deuce": "平分之后，才是真的比赛。",
    ]
    private static let openings = [
        "lap": "LAP NINE 还没开门：跑步打卡 3 次开门。", "nolook": "NO LOOK 还没开门：篮球打卡 3 次开门。",
        "moss": "MOSSWAY 还没开门：徒步或攀岩打卡 3 次开门。", "halfmoon": "HALF MOON 还没开门：随便练什么，打卡 3 次就开门。",
        "deuce": "DEUCE CLUB 还没开门：网球、匹克球或壁球打卡 3 次开门。",
    ]
}
#endif
