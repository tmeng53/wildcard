#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import CharacterEditorDomain
import DesignSystem
import DesignSystemUI
import SwiftUI

/// 穿搭, 我的衣橱 (the approved wardrobe design, 2026-11-04): the clothes the member owns, by slot,
/// three a row with their names. A piece claimed on 商店街 wears NEW until it is first tapped. The
/// colors of the piece just put on stay put above the rack while it scrolls, as the skin swatches
/// do on 长相. Locked and unclaimed pieces aren't here: they wait on 商店街.
struct WardrobePanel: View {
    let model: CharacterEditorModel
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let slot = model.picked {
                SwatchRow(model: model, slot: slot, named: true)
                    .padding(.horizontal, Space.pageMargin)
                    .padding(.top, Space.s)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    ForEach(model.wardrobe, id: \.slot) { group in
                        VStack(alignment: .leading, spacing: Space.s) {
                            SectionLabel(EditorNames.slot(group.slot))
                            LazyVGrid(
                                columns: Array(repeating: GridItem(.flexible(), spacing: Space.xs), count: 3),
                                spacing: Space.xs
                            ) {
                                ForEach(group.pieces, id: \.self) { piece in
                                    WardrobePiece(model: model, slot: group.slot, variant: piece)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Space.pageMargin)
                .padding(.vertical, Space.s)
            }
            .scrollIndicators(.hidden)
            .accessibilityIdentifier("editor.wardrobe")
        }
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
