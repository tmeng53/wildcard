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
        .padding(.top, Space.xxs)
    }
}

/// A store on the street. An open one is white with a hairline, its badge, name, Chinese name and
/// sports, and says 营业中; a closed one is grey, a lock in place of its badge, its name faded,
/// and says how it unlocks.
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
                        InkTag.new.accessibilityIdentifier("editor.store.\(store.id).new")
                    }
                }
                if store.isOpen {
                    Text("\(StoreCopy.local(store.id)) · \(StoreCopy.sports(store.id))", bundle: .module)
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
struct StoreBadge: View {
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
                if model.isBoxed(piece.variant) {
                    ReadyBox(model: model, slot: piece.slot)
                } else {
                    RackPiece(model: model, slot: piece.slot, variant: piece.variant)
                }
            }
            // The pieces still locked hang last, as boxes nobody can see into.
            ForEach(model.draft.catalog.lockedRack(of: store.id), id: \.variant) { piece in
                MysteryBox(toGo: piece.toGo, slot: piece.slot)
            }
        }
        .padding(.top, Space.xxs)
    }
}

/// A piece still locked: a 「？」 box in place of its picture and name, with how many 练了 open it
/// (Tracy, 2026-11-03: hidden at first, 制造神秘感). It can't be picked.
private struct MysteryBox: View {
    let toGo: Int
    let slot: Slot
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        VStack(spacing: Space.xxs) {
            MysteryFace()
                .aspectRatio(1, contentMode: .fit)
            Text("再练 \(toGo) 次", bundle: .module)
                .typeStyle(TypeRamp.caption)
                .foregroundStyle(Color(role: .fgMuted, in: theme))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("神秘款，再练 \(toGo) 次解锁", bundle: .module))
        .accessibilityIdentifier("editor.mystery.\(slot.rawValue)")
    }
}

/// A piece that came in but whose box this phone hasn't opened: the same 「？」 box, 「可以开了」
/// under it. A tap puts the pop-up up again with every box waiting.
private struct ReadyBox: View {
    let model: CharacterEditorModel
    let slot: Slot
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        Button(action: model.showArrivals) {
            VStack(spacing: Space.xxs) {
                MysteryFace()
                    .aspectRatio(1, contentMode: .fit)
                Text("可以开了", bundle: .module)
                    .typeStyle(TypeRamp.caption)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("新货，可以开了", bundle: .module))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("editor.ready.\(slot.rawValue)")
    }
}

/// The face of a locked piece's box: a big 「？」 on the subtle fill, in the tile's shape.
struct MysteryFace: View {
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.pick, style: .continuous)
        shape.fill(Color(role: .bgSubtle, in: theme))
            .overlay {
                Text(verbatim: "?")
                    .typeStyle(TypeRamp.scoreCard)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
            }
            .overlay { shape.strokeBorder(Color(role: .borderDefault, in: theme), lineWidth: Sizing.hairline) }
            .accessibilityHidden(true)
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
            .overlay(alignment: .topLeading) {
                if model.isNew(variant) {
                    InkTag.new
                        .padding(Space.xxs)
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("editor.tile.\(slot.rawValue).\(variant).new")
                }
            }
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
/// its Chinese name, its sports, its line, and how a closed one unlocks.
enum StoreCopy {
    static func name(_ store: String) -> Text { text(names[store], or: store) }
    static func local(_ store: String) -> Text { text(locals[store], or: store) }
    static func sports(_ store: String) -> Text { text(sportLines[store], or: "") }
    static func tagline(_ store: String) -> Text { text(taglines[store], or: "") }
    static func unlock(_ store: String) -> Text { text(unlocks[store], or: "") }

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
    private static let unlocks = [
        "lap": "跑步 3 次解锁", "nolook": "篮球 3 次解锁", "moss": "攀岩或徒步 3 次解锁", "halfmoon": "随便练 3 次解锁",
        "deuce": "网球类 3 次解锁",
    ]
}
#endif
