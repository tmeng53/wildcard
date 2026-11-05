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

/// Inside a store: its line and its rack, three a row, each piece as the member finds it.
struct StoreRack: View {
    let model: StreetModel
    let store: EditorChoices.Store
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        StoreCopy.tagline(store.id)
            .typeStyle(TypeRamp.footnote)
            .foregroundStyle(Color(role: .fgMuted, in: theme))
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.xs), count: 3), spacing: Space.xs) {
            ForEach(model.catalog.rack(of: store.id), id: \.variant) { piece in
                RackPiece(model: model, slot: piece.slot, variant: piece.variant)
            }
            // The pieces still locked hang last, as boxes nobody can see into.
            ForEach(model.catalog.lockedRack(of: store.id), id: \.variant) { piece in
                MysteryBox(model: model, store: store.id, toGo: piece.toGo, slot: piece.slot)
            }
        }
        .padding(.top, Space.xxs)
    }
}

/// A piece still locked: a 「？」 box in place of its picture and name, with how many 练了 open it
/// (Tracy, 2026-11-03: hidden at first, 制造神秘感). A tap tells which sports count.
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
            VStack(spacing: Space.xxs) {
                MysteryFace()
                    .aspectRatio(1, contentMode: .fit)
                Text("再练 \(toGo) 次", bundle: .module)
                    .typeStyle(TypeRamp.caption)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("神秘款，再练 \(toGo) 次解锁", bundle: .module))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("editor.mystery.\(slot.rawValue)")
    }
}

/// A piece that came in but whose box this phone hasn't opened: the same 「？」 box, 「可以开了」
/// under it. A tap puts the pop-up up again with every box waiting.
struct ReadyBox: View {
    let model: StreetModel
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

/// One piece on a rack: its picture on its own, as a shop shows it, over its name. One that came
/// in wears NEW and offers 领取; one in the wardrobe says 已拥有 and is tried on in the editor.
struct RackPiece: View {
    let model: StreetModel
    let slot: Slot
    let variant: String
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        let shelf = model.shelf(variant)
        if shelf == .boxed {
            ReadyBox(model: model, slot: slot)
        } else {
            VStack(spacing: Space.xxs) {
                PickTile(
                    EditorNames.variant(variant, in: slot), isSelected: false,
                    action: { model.tap(variant) },
                    picture: { picture }
                )
                .accessibilityIdentifier("editor.tile.\(slot.rawValue).\(variant)")
                .overlay(alignment: .topLeading) {
                    if shelf == .new {
                        InkTag.new
                            .padding(Space.xxs)
                            .allowsHitTesting(false)
                            .accessibilityIdentifier("editor.tile.\(slot.rawValue).\(variant).new")
                    }
                }
                EditorNames.variant(variant, in: slot)
                    .typeStyle(TypeRamp.caption)
                    .foregroundStyle(Color(role: shelf == .owned ? .fgMuted : .fgDefault, in: theme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityHidden(true)
                if shelf == .owned {
                    Text("已拥有", bundle: .module)
                        .typeStyle(TypeRamp.label)
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                        .lineLimit(1)
                        .accessibilityIdentifier("editor.tile.\(slot.rawValue).\(variant).owned")
                }
            }
        }
    }

    @ViewBuilder private var picture: some View {
        if let preview = model.preview(of: variant) {
            Thumbnail(outfit: preview.outfit, only: slot, crop: ThumbnailCrop.of(slot), cache: model.thumbnails)
                .padding(Space.xs)
        }
    }
}

/// 「练这些运动解锁」 and the sports, as mist pills; 「练什么都算」 when any sport counts.
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
                    pill(Text("练什么都算", bundle: .module))
                } else {
                    ForEach(sports, id: \.self) { pill($0.name) }
                }
            }
        }
        .padding(Space.s)
        .frame(width: 220, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("street.tip")
    }

    private func pill(_ word: Text) -> some View {
        word
            .typeStyle(TypeRamp.footnoteEmphasis)
            .foregroundStyle(Color(role: .fgDefault, in: theme))
            .padding(.horizontal, Space.s)
            .padding(.vertical, Space.xxs)
            .background(Color(role: .bgSubtle, in: theme), in: Capsule())
    }
}

/// Pills that wrap onto the next line where they don't fit.
struct FlowRow: Layout {
    let spacing: Double

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * Double(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var top = bounds.minY
        for row in rows(width: bounds.width, subviews: subviews) {
            var leading = bounds.minX
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
