#if os(iOS)
import DesignSystem
import DesignSystemUI
import MeDomain
import SwiftUI

/// The top of a card's back side: the member's name and number, and, on a squadmate's side opened
/// from their 出赛表 (穿搭, 徽章), 「‹ side」 back to the 出赛表 with how many it holds, over a
/// hairline. One header for every such side, so going back looks and sits the same on each
/// (Tracy, 2026-11-11).
struct CardSideHeader: View {
    /// A side's way back to the 出赛表.
    struct Back {
        let title: Text
        let count: Text?
        let identifier: String
        let action: () -> Void
    }

    let face: PlayerCardFace
    /// Nil on the member's own card, whose back opens from its front.
    var back: Back?
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(face.character.nickname)
                    .typeStyle(TypeRamp.headline)
                    .foregroundStyle(Color(role: .fgOnInk, in: theme))
                    .lineLimit(1)
                Spacer(minLength: Space.s)
                if let number = face.number {
                    Text(verbatim: "#\(number.text)")
                        .typeStyle(TypeRamp.scoreSmall)
                        .foregroundStyle(Color(role: .fgOnInkMuted, in: theme))
                        .monospacedDigit()
                }
            }
            if let back {
                HStack(alignment: .firstTextBaseline) {
                    Button(action: back.action) {
                        Label {
                            back.title
                        } icon: {
                            Image(systemName: "chevron.left")
                        }
                        .typeStyle(TypeRamp.calloutEmphasis)
                        .foregroundStyle(Color(role: .fgOnInk, in: theme))
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityIdentifier(back.identifier)
                    Spacer(minLength: Space.xs)
                    if let count = back.count {
                        count
                            .typeStyle(TypeRamp.caption)
                            .foregroundStyle(Color(role: .fgOnInkMuted, in: theme))
                    }
                }
                .padding(.vertical, Space.xs)
                .overlay(alignment: .bottom) { Hairline(on: .ink) }
            }
        }
    }
}
#endif
