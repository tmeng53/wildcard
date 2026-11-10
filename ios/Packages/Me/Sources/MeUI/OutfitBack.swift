#if os(iOS)
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
    @Environment(\.sceneTheme) private var theme

    private var ink: Color { Color(role: .fgOnInk, in: theme) }
    private var muted: Color { Color(role: .fgOnInkMuted, in: theme) }
    private var pieces: Int { WornOutfitList.count(face.character.outfit) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(face.character.nickname)
                    .typeStyle(TypeRamp.headline)
                    .foregroundStyle(ink)
                    .lineLimit(1)
                Spacer(minLength: Space.s)
                if let number = face.number {
                    Text(verbatim: "#\(number.text)")
                        .typeStyle(TypeRamp.scoreSmall)
                        .foregroundStyle(muted)
                        .monospacedDigit()
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Button(action: toSchedule) {
                    Label {
                        Text(copy: "穿搭", bundle: .module)
                    } icon: {
                        Image(systemName: "chevron.left")
                    }
                    .typeStyle(TypeRamp.calloutEmphasis)
                    .foregroundStyle(ink)
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityIdentifier("me.cardOutfitBack")
                Spacer(minLength: Space.xs)
                Text(copy: "card.outfit.count \(pieces)", bundle: .module)
                    .typeStyle(TypeRamp.caption)
                    .foregroundStyle(muted)
            }
            .padding(.top, Space.xs)
            .padding(.bottom, Space.xs)
            .overlay(alignment: .bottom) { Hairline(on: .ink) }
            ScrollView {
                WornOutfitList(outfit: face.character.outfit)
                    .padding(.vertical, Space.xxs)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(.horizontal, Space.xs)
        .padding(.top, Space.xs)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
#endif
