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

/// Inside a store: its rack, three a row, each piece on a mist card as the member finds it
/// (approved 2026-11-08).
struct StoreRack: View {
    let model: StreetModel
    let store: EditorChoices.Store

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.xs), count: 3), spacing: Space.xs) {
            ForEach(model.catalog.rack(of: store.id), id: \.variant) { piece in
                RackPiece(model: model, slot: piece.slot, variant: piece.variant)
            }
            // The pieces still locked come last, as cardboard boxes nobody can see into.
            ForEach(model.catalog.lockedRack(of: store.id), id: \.variant) { piece in
                MysteryBox(model: model, store: store.id, toGo: piece.toGo, slot: piece.slot)
            }
        }
        .padding(.top, Space.xxs)
    }
}

/// A card on the rack: the mist tile every piece and box stands on, its picture over its name and
/// a line under that.
private struct RackCard<Picture: View, Status: View>: View {
    @ViewBuilder let picture: Picture
    let name: Text
    let muted: Bool
    @ViewBuilder let status: Status
    @Environment(\.sceneTheme) private var theme
    private let side: Double = 84
    private let height: Double = 150

    var body: some View {
        VStack(spacing: Space.xxs) {
            picture
                .frame(width: side, height: side)
            name
                .typeStyle(TypeRamp.footnoteEmphasis)
                .foregroundStyle(Color(role: muted ? .fgMuted : .fgDefault, in: theme))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            status
        }
        .padding(.horizontal, Space.xs - Space.xxs / 2)
        .padding(.top, Space.xs + Space.xxs / 2)
        .padding(.bottom, Space.s)
        .frame(maxWidth: .infinity, minHeight: height, alignment: .top)
        .background(
            Color(role: .bgSubtle, in: theme), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}

/// A piece still locked: a cardboard box with a 「?」 in place of its picture, 神秘款 for its name
/// and how many 练了 open it (Tracy, 2026-11-03: hidden at first, 制造神秘感). A tap tells which
/// sports count.
struct MysteryBox: View {
    let model: StreetModel
    let store: String
    let toGo: Int
    let slot: Slot
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        Button {
            model.tip = store
        } label: {
            RackCard(
                picture: {
                    ShopCarton()
                        .frame(width: 72, height: 60)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                },
                name: Text("神秘款", bundle: .module), muted: true,
                status: {
                    Text("再练 \(toGo) 次", bundle: .module)
                        .typeStyle(TypeRamp.caption)
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            )
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("神秘款，再练 \(toGo) 次解锁", bundle: .module))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("editor.mystery.\(slot.rawValue)")
    }
}

/// One piece on a rack: its picture on its own, as a shop shows it, over its name. One that came
/// in shows as itself, never a box, wears NEW and offers 领取; one in the wardrobe is dimmed, says
/// 已拥有 and is tried on in the editor (Tracy, 2026-11-06).
struct RackPiece: View {
    let model: StreetModel
    let slot: Slot
    let variant: String
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        let shelf = model.shelf(variant)
        let isNew = shelf == .new || shelf == .boxed
        Button {
            model.tap(variant)
        } label: {
            RackCard(
                picture: {
                    picture
                        // Already in the wardrobe: dimmed, so what is still to take stands out.
                        .opacity(shelf == .owned ? 0.45 : 1)
                },
                name: EditorNames.variant(variant, in: slot), muted: shelf == .owned,
                // A hidden copy of the line keeps its room in the card, so the real one over it
                // never covers the name, at any text size.
                status: { status(shelf, isNew: isNew).hidden() }
            )
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(EditorNames.variant(variant, in: slot))
        // What the card's line says, which sits outside the button.
        .accessibilityValue(
            isNew ? Text("领取", bundle: .module) : shelf == .owned ? Text("已拥有", bundle: .module) : Text(verbatim: "")
        )
        .accessibilityIdentifier("editor.tile.\(slot.rawValue).\(variant)")
        // NEW and the line under the name sit over the card, outside its button, so each is its
        // own element as a UI test finds it.
        .overlay(alignment: .topLeading) {
            if isNew {
                InkTag.new
                    .padding(Space.xs - Space.xxs / 2)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("editor.tile.\(slot.rawValue).\(variant).new")
            }
        }
        .overlay(alignment: .bottom) {
            status(shelf, isNew: isNew)
                .padding(.bottom, Space.s)
                .allowsHitTesting(false)
        }
    }

    /// 领取 on a piece that came in, 已拥有 on one in the wardrobe.
    @ViewBuilder
    private func status(_ shelf: StreetModel.Shelf, isNew: Bool) -> some View {
        if isNew {
            Text("领取", bundle: .module)
                .typeStyle(TypeRamp.label)
                .foregroundStyle(Color(role: .fgOnBrand, in: theme))
                .lineLimit(1)
                .padding(.horizontal, Space.s)
                .padding(.vertical, Space.xxs / 2)
                .background(Color(role: .bgBrand, in: theme), in: Capsule())
                .padding(.top, Space.xxs / 2)
        } else if shelf == .owned {
            Text("已拥有", bundle: .module)
                .typeStyle(TypeRamp.label)
                .foregroundStyle(Color(role: .fgMuted, in: theme))
                .lineLimit(1)
                .accessibilityIdentifier("editor.tile.\(slot.rawValue).\(variant).owned")
        }
    }

    @ViewBuilder private var picture: some View {
        if let preview = model.preview(of: variant) {
            Thumbnail(outfit: preview.outfit, only: slot, crop: ThumbnailCrop.of(slot), cache: model.thumbnails)
        }
    }
}

/// 「练这些运动解锁」 and the sports, as mist pills; 「什么运动都行」 when any sport counts.
struct SportsTip: View {
    let sports: [Sport]
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("练这些运动解锁", bundle: .module)
                .typeStyle(TypeRamp.label)
                .foregroundStyle(Color(role: .fgMuted, in: theme))
            FlowRow(spacing: Space.xs) {
                if sports.isEmpty {
                    SportPill(word: Text("什么运动都行", bundle: .module))
                } else {
                    ForEach(sports, id: \.self) { SportPill(word: $0.name) }
                }
            }
        }
        .padding(Space.s)
        .frame(width: 220, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("street.tip")
    }
}

/// A sport as a mist pill, in 「练这些运动解锁」 and under the street's storefront.
struct SportPill: View {
    let word: Text
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        word
            .typeStyle(TypeRamp.footnoteEmphasis)
            .foregroundStyle(Color(role: .fgDefault, in: theme))
            .padding(.horizontal, Space.s)
            .padding(.vertical, Space.xxs)
            .background(Color(role: .bgSubtle, in: theme), in: Capsule())
    }
}

/// Pills that wrap onto the next line where they don't fit, each line from the leading edge or
/// centred.
struct FlowRow: Layout {
    let spacing: Double
    var centred = false

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * Double(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var top = bounds.minY
        for row in rows(width: bounds.width, subviews: subviews) {
            var leading = bounds.minX + (centred ? (bounds.width - row.width) / 2 : 0)
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: leading, y: top), proposal: ProposedViewSize(size))
                leading += size.width + spacing
            }
            top += row.height + spacing
        }
    }

    struct Row {
        var items: [Int] = []
        var width: Double = 0
        var height: Double = 0
    }

    private func rows(width: Double, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if let last = rows.last, !last.items.isEmpty, last.width + spacing + size.width > width {
                rows.append(Row())
            }
            let gap = rows[rows.count - 1].items.isEmpty ? 0 : spacing
            rows[rows.count - 1].items.append(index)
            rows[rows.count - 1].width += gap + size.width
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}
#endif
