#if os(iOS)
import DesignSystem
import DesignSystemUI
import MeDomain
import SwiftUI

/// A squadmate's player card in a sheet, opened from their name on the home or in 小队设置: the
/// same card as 我's, turning over to their badge board, whose badges open with no 装备.
public struct SquadmateCardSheet: View {
    @Bindable private var model: SquadmateCardModel
    @Environment(\.sceneTheme) private var theme

    public init(model: SquadmateCardModel) {
        self.model = model
    }

    public var body: some View {
        Group {
            switch model.load {
            case .loading:
                MeLoading()
            case .failed:
                MeFailed { Task { await model.reload() } }
            case .loaded(let face):
                ScrollView {
                    PlayerCard(face: face, equip: nil)
                        .padding(.top, Space.xl)
                        .padding(.bottom, Space.l)
                        .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(role: .bgCanvas, in: theme))
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task { await model.reload() }
    }
}
#endif
