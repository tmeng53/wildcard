#if os(iOS)
import AvatarArt
import AvatarDomain
import DesignSystem
import DesignSystemUI
import SwiftUI

/// What a squadmate wears, on their player card's back (Tracy, 2026-11-10, A): a row a piece,
/// head to foot and the prop last, each with the piece on its own, its name, its slot and store,
/// and a limited store's tag (冬季限定), since a piece is hard to tell from the small character.
/// Drawn on the card's ink.
public struct WornOutfitList: View {
    private let pieces: [WornPiece]
    private let outfit: Outfit
    @State private var thumbnails = ThumbnailCache()
    @Environment(\.sceneTheme) private var theme

    /// `pieces` from `PlaceholderCharacter.worn(outfit)`, read once by the caller, which reads
    /// art files.
    public init(outfit: Outfit, pieces: [WornPiece]) {
        (self.outfit, self.pieces) = (outfit, pieces)
    }

    public var body: some View {
        VStack(spacing: 0) {
            ForEach(pieces) { piece in row(piece) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("card.outfit")
    }

    private func row(_ piece: WornPiece) -> some View {
        HStack(spacing: Space.s) {
            WornPieceTile(outfit: outfit, slot: piece.slot, size: Self.tile, cache: thumbnails)
            VStack(alignment: .leading, spacing: Space.xxs / 2) {
                EditorNames.variant(piece.piece, in: piece.slot)
                    .typeStyle(TypeRamp.calloutEmphasis)
                    .foregroundStyle(Color(role: .fgOnInk, in: theme))
                    .lineLimit(1)
                place(piece)
                    .typeStyle(TypeRamp.caption)
                    .foregroundStyle(Color(role: .fgOnInkMuted, in: theme))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let store = piece.store, let tag = LimitedTag(store: store, onInk: true) { tag }
        }
        .padding(.horizontal, Space.xxs)
        .frame(height: Self.rowHeight)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("card.outfitPiece")
    }

    /// 上衣 · 粉雪日: the slot, and the store for a piece on a rack.
    private func place(_ piece: WornPiece) -> Text {
        let slot = EditorNames.slot(piece.slot)
        guard let store = piece.store else { return slot }
        return slot + Text(verbatim: " · ") + StoreCopy.local(store)
    }

    /// From the approved mock-up.
    private static let tile: Double = 40
    private static let rowHeight: Double = 52
}

/// The first pieces a squadmate wears, small, beside 穿搭 on their card's back.
public struct WornOutfitPeek: View {
    private let outfit: Outfit
    private let count: Int
    /// Read once the peek shows, since it reads art files.
    @State private var slots: [Slot] = []
    @State private var thumbnails = ThumbnailCache()

    public init(outfit: Outfit, count: Int = 2) {
        (self.outfit, self.count) = (outfit, count)
    }

    public var body: some View {
        HStack(spacing: Space.xxs) {
            ForEach(slots, id: \.self) { slot in
                WornPieceTile(outfit: outfit, slot: slot, size: Self.tile, cache: thumbnails)
            }
        }
        .frame(height: Self.tile)
        .task(id: outfit) { slots = PlaceholderCharacter.worn(outfit).prefix(count).map(\.slot) }
        .accessibilityHidden(true)
    }

    private static let tile: Double = 24
}

/// One piece on its own on a light tile.
private struct WornPieceTile: View {
    let outfit: Outfit
    let slot: Slot
    let size: Double
    let cache: ThumbnailCache
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        Thumbnail(outfit: outfit, only: slot, crop: ThumbnailCrop.of(slot), cache: cache)
            .padding(size / 12)
            .frame(width: size, height: size)
            .background(
                Color(role: .bgSubtle, in: theme),
                in: RoundedRectangle(cornerRadius: Radius.thumbnail, style: .continuous))
    }
}
#endif
