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

/// 领取's sheet: the piece big, its name and store, and the brand's 52-point 「领取」. Nothing is
/// bought. Pulled down or tapped outside, the piece keeps NEW.
struct ClaimSheet: View {
    struct Piece: Identifiable {
        let id: String
    }

    static let height: Double = 380

    let model: StreetModel
    let piece: String
    @Environment(\.sceneTheme) private var theme
    private let side: Double = 160

    var body: some View {
        let preview = model.preview(of: piece)
        let store = model.catalog.storeOf[piece] ?? ""
        VStack(spacing: Space.xs) {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Color(role: .bgSubtle, in: theme))
                .frame(width: side, height: side)
                .overlay {
                    if let preview {
                        Thumbnail(
                            outfit: preview.outfit, only: preview.slot, crop: ThumbnailCrop.of(preview.slot),
                            cache: model.thumbnails
                        )
                        .padding(Space.m)
                    }
                }
            if let preview {
                EditorNames.variant(piece, in: preview.slot)
                    .typeStyle(TypeRamp.headline)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .padding(.top, Space.xs)
            }
            Text("\(StoreCopy.name(store)) · \(StoreCopy.local(store))", bundle: .module)
                .typeStyle(TypeRamp.footnote)
                .foregroundStyle(Color(role: .fgMuted, in: theme))
            Button {
                Task { await model.claim(piece) }
            } label: {
                Text("领取", bundle: .module).frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .accentTone(.brand)
            .padding(.top, Space.m)
            .accessibilityIdentifier("street.claim")
        }
        .padding(.horizontal, Space.l)
        .padding(.top, Space.l)
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("street.sheet")
    }
}

/// 「已放进衣橱 · <name> · 穿上看看」, the notice a claim drops in; a tap tries the piece on.
struct ClaimedBanner: View {
    let model: StreetModel
    let piece: String

    var body: some View {
        let preview = model.preview(of: piece)
        NoticeBanner(
            Text("已放进衣橱", bundle: .module),
            detail: preview.map { Text("\(EditorNames.variant(piece, in: $0.slot)) · 穿上看看", bundle: .module) },
            showsChevron: true
        ) {
            ZStack {
                Color(role: .bgCanvas, in: .gym)
                if let preview {
                    Thumbnail(
                        outfit: preview.outfit, only: preview.slot, crop: ThumbnailCrop.of(preview.slot),
                        cache: model.thumbnails
                    )
                    .padding(Space.xxs)
                }
            }
            .accessibilityHidden(true)
        }
    }
}
#endif
