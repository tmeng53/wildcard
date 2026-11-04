#if os(iOS)
import DesignSystem
import DesignSystemUI
import MeDomain
import SwiftUI

/// A squadmate's player card, opened from their name on the home or in 小队设置 and shown with
/// `cardPopup` in the middle of the screen: the same card as 我's, turning over to their badge
/// board, whose badges open with no 装备. While it is read, or if it can't be, a solid card of the
/// same size stands in.
public struct SquadmateCardPopup: View {
    @Bindable private var model: SquadmateCardModel
    @Environment(\.sceneTheme) private var theme

    /// The card's width, for what the app shows over it.
    public static var width: Double { PlayerCard.size.width }

    public init(model: SquadmateCardModel) {
        self.model = model
    }

    public var body: some View {
        Group {
            switch model.load {
            case .loading:
                standIn { TicketSpinner(on: .light(.bgCanvas)).accessibilityIdentifier("me.loading") }
            case .failed:
                standIn { MeFailed { Task { await model.reload() } } }
            case .loaded(let face):
                // The hint sits on the dim, so it is in the ink's own type colour.
                PlayerCard(face: face, equip: nil, hint: .fgOnInk)
            }
        }
        .task { await model.reload() }
    }

    private func standIn<Content: View>(_ content: () -> Content) -> some View {
        content()
            .frame(width: PlayerCard.size.width, height: PlayerCard.size.height)
            .background(
                Color(role: .bgCanvas, in: theme),
                in: RoundedRectangle(cornerRadius: Radius.card + Space.xxs, style: .continuous))
    }
}
#endif
