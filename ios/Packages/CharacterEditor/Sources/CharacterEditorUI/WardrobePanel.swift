#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import CharacterEditorDomain
import DesignSystem
import DesignSystemUI
import SwiftUI

/// 穿搭, 我的衣橱 (the approved wardrobe design, 2026-11-04): the clothes the member owns, one slot
/// at a time (上衣, 下装, 鞋子, 头饰, 配饰 on a bar of their own, Tracy 2026-11-05, since all of them in
/// one list was too many to look through; a slot with nothing in it yet keeps its tab and says
/// 还是空的), three a row with their names. The bar follows the piece
/// last put on, so 穿上看看 opens on its slot. A piece claimed on 商店街 wears NEW until it is first
/// tapped. The colors of the piece just put on stay put above the rack, as the skin swatches do on
/// 长相. Locked and unclaimed pieces aren't here: they wait on 商店街.
struct WardrobePanel: View {
    let model: CharacterEditorModel
    /// The slot the member tapped on the bar; nil follows the piece last put on.
    @State private var chosen: Slot?

    var body: some View {
        let wardrobe = model.wardrobe
        let shown = shownSlot(in: wardrobe)
        VStack(alignment: .leading, spacing: 0) {
            if let shown {
                CategoryBar(
                    wardrobe.map {
                        CategoryBarItem(
                            id: $0.slot, title: EditorNames.slot($0.slot),
                            accessibilityIdentifier: "editor.wardrobe.\($0.slot.rawValue)")
                    },
                    selection: Binding {
                        shown
                    } set: {
                        chosen = $0
                    }
                )
                .padding(.top, Space.xs)
            }
            if let slot = model.picked, slot == shown {
                SwatchRow(model: model, slot: slot, named: true)
                    .padding(.horizontal, Space.pageMargin)
                    .padding(.top, Space.s)
            }
            ScrollView {
                let pieces = wardrobe.first { $0.slot == shown }?.pieces ?? []
                if let shown, !pieces.isEmpty {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: Space.xs), count: 3),
                        spacing: Space.xs
                    ) {
                        ForEach(pieces, id: \.self) { piece in
                            WardrobePiece(model: model, slot: shown, variant: piece)
                        }
                    }
                    .padding(.horizontal, Space.pageMargin)
                    .padding(.vertical, Space.s)
                } else {
                    // A slot the member owns nothing in yet still has its tab.
                    StateView(Text(copy: "还是空的", bundle: .module))
                        .padding(.horizontal, Space.pageMargin)
                        .padding(.vertical, Space.xl)
                        .accessibilityIdentifier("editor.wardrobe.empty")
                }
            }
            .scrollIndicators(.hidden)
            .accessibilityIdentifier("editor.wardrobe")
        }
        // A piece put on from elsewhere (穿上看看) brings its slot up.
        .onChange(of: model.picked) { _, picked in
            if let picked { chosen = picked }
        }
    }

    /// The slot on show: the one tapped on the bar, else the piece last put on's, else the first.
    private func shownSlot(in wardrobe: [(slot: Slot, pieces: [String])]) -> Slot? {
        let slots = wardrobe.map(\.slot)
        for slot in [chosen, model.picked] {
            if let slot, slots.contains(slot) { return slot }
        }
        return slots.first
    }
}

/// A piece in the wardrobe: its picture worn in the member's colors, its name, NEW until tapped.
private struct WardrobePiece: View {
    let model: CharacterEditorModel
    let slot: Slot
    let variant: String
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        VStack(spacing: Space.xxs) {
            PickTile(
                EditorNames.variant(variant, in: slot),
                isSelected: model.draft.picks.variants[slot] == variant,
                action: { model.wear(variant, for: slot) },
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

    /// The draft wearing the piece, so it shows in the colors it would be worn in.
    private var preview: Outfit {
        var draft = model.draft
        draft.pick(variant, for: slot)
        return draft.outfit
    }
}
#endif
