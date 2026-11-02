#if os(iOS)
import SwiftUI

extension View {
    /// Reads 今天's home again each minute while it is on screen, so teammates' check-ins show
    /// without leaving the app (`TodayModel.reread()`).
    func rereadsEachMinute(_ model: TodayModel) -> some View {
        task {
            while !Task.isCancelled {
                try? await Task.sleep(for: TodayModel.rereadEvery)
                guard !Task.isCancelled else { return }
                await model.reread()
            }
        }
    }
}
#endif
