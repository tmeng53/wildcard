#if canImport(SwiftUI)
import AvatarArt
import AvatarDomain
import AvatarUI
import CharacterEditorDomain
import DesignSystem
import DesignSystemUI
import SwiftUI

/// The open tab's choices: color swatches over a grid of picture tiles, or the persona
/// carousel. On 样子 the skin or coat swatches stay put above the species while they scroll.
struct ChoicesPanel: View {
    let model: CharacterEditorModel

    var body: some View {
        switch model.tab {
        case .persona:
            PersonaCarousel(model: model)
                .frame(maxHeight: .infinity, alignment: .top)
        case .look:
            VStack(alignment: .leading, spacing: 0) {
                SwatchRow(model: model, slot: "body")
                    .padding(.horizontal, Space.pageMargin)
                scroll {
                    ForEach(model.draft.catalog.species) { species in
                        ChoiceSection(label: EditorNames.species(species.id)) {
                            TileGrid(model: model, slot: "body", variants: species.bodies, offersNothing: false)
                        }
                    }
                }
            }
        case .hair:
            scroll {
                ChoiceSection(label: nil) {
                    SwatchRow(model: model, slot: "hair")
                    TileGrid(model: model, slot: "hair", variants: variants("hair"), offersNothing: false)
                }
            }
        case .face:
            scroll {
                ChoiceSection(label: Text("眼睛", bundle: .module)) {
                    SwatchRow(model: model, slot: "eyes")
                    TileGrid(model: model, slot: "eyes", variants: variants("eyes"), offersNothing: false)
                }
                ChoiceSection(label: Text("眉毛", bundle: .module)) {
                    SwatchRow(model: model, slot: "brows")
                    TileGrid(model: model, slot: "brows", variants: variants("brows"), offersNothing: true)
                }
                ChoiceSection(label: Text("嘴巴", bundle: .module)) {
                    TileGrid(model: model, slot: "mouth", variants: variants("mouth"), offersNothing: false)
                }
                ChoiceSection(label: Text("脸蛋", bundle: .module)) {
                    TileGrid(model: model, slot: "cheeks", variants: variants("cheeks"), offersNothing: true)
                }
                ChoiceSection(label: Text("眼镜", bundle: .module)) {
                    TileGrid(model: model, slot: "glasses", variants: variants("glasses"), offersNothing: true)
                }
            }
        case .outfit:
            ShoppingStreet(model: model)
        case .prop:
            scroll {
                ChoiceSection(label: nil) {
                    TileGrid(model: model, slot: "prop", variants: model.draft.catalog.props, offersNothing: true)
                }
            }
        }
    }

    private func variants(_ slot: Slot) -> [String] {
        model.draft.catalog.variants[slot] ?? []
    }

    private func scroll(@ViewBuilder content: () -> some View) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                content()
            }
            .padding(.horizontal, Space.pageMargin)
            .padding(.vertical, Space.s)
        }
        .scrollIndicators(.hidden)
    }
}

/// A group of choices under a short label, such as 眼睛.
private struct ChoiceSection<Content: View>: View {
    let label: Text?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if let label {
                SectionLabel(label)
            }
            content
        }
    }
}

/// Four picture tiles a row: the character in each choice, and first a tile that takes the
/// piece off when the slot can be left empty.
private struct TileGrid: View {
    let model: CharacterEditorModel
    let slot: Slot
    let variants: [String]
    let offersNothing: Bool
    @Environment(\.sceneTheme) private var theme
    private let nothingGlyph: Double = 26

    var body: some View {
        let choices: [String?] = (offersNothing ? [nil] : []) + variants.map { $0 }
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.s), count: 4), spacing: Space.s) {
            ForEach(choices, id: \.self) { variant in
                PickTile(
                    variant.map { EditorNames.variant($0, in: slot) } ?? EditorNames.nothing(in: slot),
                    isSelected: model.draft.picks.variants[slot] == variant,
                    action: { model.pick(variant, for: slot) },
                    picture: { picture(variant) }
                )
                .accessibilityIdentifier("editor.tile.\(slot.rawValue).\(variant ?? "none")")
            }
        }
    }

    @ViewBuilder
    private func picture(_ variant: String?) -> some View {
        if let variant {
            Thumbnail(outfit: preview(variant), crop: ThumbnailCrop.of(slot), cache: model.thumbnails)
        } else {
            Image(systemName: "circle.slash")
                .font(.system(size: nothingGlyph, weight: .regular))
                .foregroundStyle(Color(role: .fgSubtle, in: theme))
        }
    }

    /// The character as it would look wearing `variant`, by the draft's own rules.
    private func preview(_ variant: String) -> Outfit {
        var draft = model.draft
        draft.pick(variant, for: slot)
        return draft.outfit
    }
}

/// The preset colors of what `slot` wears, the first being the art's own (原色), after the
/// piece's name when `named`. Nothing when it keeps its own colors.
struct SwatchRow: View {
    let model: CharacterEditorModel
    let slot: Slot
    var named = false
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        let catalog = model.draft.catalog
        if let variant = model.draft.picks.variants[slot],
            let original = catalog.originals[slot]?[variant]
        {
            // Clothes list their art's own color first; the rest get a 原色 swatch before theirs.
            let listed = catalog.swatches(for: slot, wearing: variant)
            let colors = listed.first == original ? Array(listed.dropFirst()) : listed
            ScrollView(.horizontal) {
                HStack(spacing: Space.xxs) {
                    if named {
                        EditorNames.variant(variant, in: slot)
                            .typeStyle(TypeRamp.caption)
                            .foregroundStyle(Color(role: .fgMuted, in: theme))
                            .padding(.trailing, Space.xxs)
                    }
                    swatch(original, value: nil, label: Text("原色", bundle: .module), index: 0)
                    ForEach(Array(colors.enumerated()), id: \.offset) { index, color in
                        swatch(color, value: color, label: Text("颜色 \(index + 1)", bundle: .module), index: index + 1)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .horizontalScrollFade()
        }
    }

    private func swatch(_ color: RGBAColor, value: RGBAColor?, label: Text, index: Int) -> some View {
        Swatch(Color(color), label: label, isSelected: model.draft.picks.colors[slot] == value) {
            model.pickColor(value, for: slot)
        }
        .accessibilityIdentifier("editor.swatch.\(slot.rawValue).\(index)")
    }
}
#endif
