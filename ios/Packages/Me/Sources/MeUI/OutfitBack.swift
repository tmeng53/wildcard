#if os(iOS)
import AvatarArt
import CharacterEditorUI
import DesignSystem
import DesignSystemUI
import MeDomain
import SwiftUI

/// What a squadmate wears, on their card's back in place of their 出赛表 (Tracy, 2026-11-10, A):
/// their name and number, 「‹ 穿搭」 back to the 出赛表 with how many pieces, then a row a piece.
struct OutfitBack: View {
    let face: PlayerCardFace
    let toSchedule: () -> Void
    /// Read once the side shows, since it reads art files.
    @State private var worn: [WornPiece] = []
    private var pieces: Int { worn.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardSideHeader(
                face: face,
                back: CardSideHeader.Back(
                    title: Text(copy: "穿搭", bundle: .module),
                    count: pieces > 0 ? Text(copy: "card.outfit.count \(pieces)", bundle: .module) : nil,
                    identifier: "me.cardOutfitBack", action: toSchedule))
            ScrollView {
                WornOutfitList(outfit: face.character.outfit, pieces: worn)
                    .padding(.vertical, Space.xxs)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(.horizontal, Space.xs)
        .padding(.top, Space.xs)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: face.character.outfit) { worn = PlaceholderCharacter.worn(face.character.outfit) }
    }
}
#endif
