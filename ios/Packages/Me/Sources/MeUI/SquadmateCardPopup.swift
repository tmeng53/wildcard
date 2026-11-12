#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import MeDomain
import SwiftUI

/// A player's card, opened from their name on the home or in 小队 and shown with `cardPopup` in
/// the middle of the screen: the same card as 我's, turning over to their badge board, whose
/// badges open with 装备 only on the member's own card. While it is read, or if it can't be, a solid card of the
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
                PlayerCard(face: face, equip: equip, hint: .fgOnInk)
            }
        }
        .task { await model.reload() }
    }

    /// The member's own card wears a title from a badge's card; a squadmate's shows no 装备.
    private var equip: ((Wearable) -> Void)? {
        guard model.canEquip else { return nil }
        return { wearable in Task { await model.equip(wearable) } }
    }

    private func standIn<Content: View>(_ content: () -> Content) -> some View {
        content()
            .frame(width: PlayerCard.size.width, height: PlayerCard.size.height)
            .background(
                Color(role: .bgCanvas, in: theme),
                in: TradingCard.shape)
    }
}
#endif
