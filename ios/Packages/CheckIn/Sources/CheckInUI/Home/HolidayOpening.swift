#if os(iOS)
import AvatarArt
import AvatarUI
import DesignSystem
import DesignSystemUI
import SwiftUI

/// A holiday's opening over the whole home until 进场 (`TodayModel+Opening.swift`).
struct HolidayOpening: ViewModifier {
    let model: TodayModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if let opening = model.opening {
                    OpeningView(
                        opening, squad: model.openingSquad, squadName: model.home?.squad.name,
                        language: AppLanguage.current.rawValue,
                        onPlayed: { model.cheerInOpening() }, onEnter: { model.enterFromOpening() },
                        label: { Text("进场", bundle: .module) }
                    )
                    .transition(.move(edge: .top))
                }
            }
            .animation(.wildcard(Motion.page, reduceMotion: reduceMotion), value: model.opening == nil)
    }
}
#endif
