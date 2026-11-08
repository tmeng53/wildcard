import Contracts
import DesignSystem
import RecapUI
import SwiftUI

extension View {
    /// The 战报 full screen over the app, and where its last page leads: a scene picked there ends
    /// its reveal where home takes over, and 去安排下周 opens 出赛表 on the week after it.
    func presentsRecap(
        _ recap: RecapShelf, land: @escaping (SceneTheme, Date) -> Void, open: @escaping (AppDestination) -> Void
    ) -> some View {
        fullScreenCover(isPresented: Binding(get: { recap.open != nil }, set: { if !$0 { recap.open = nil } })) {
            if let story = recap.open { RecapView(model: story, autoAdvances: !LaunchOptions.recapManual) }
        }
        .onChange(of: recap.picks) {
            if let picked = recap.picked { land(picked.scene, picked.coveredAt) }
        }
        .onChange(of: recap.planRequests) {
            if let week = recap.weekToPlan { open(.scheduleWeek(week)) }
        }
    }
}
