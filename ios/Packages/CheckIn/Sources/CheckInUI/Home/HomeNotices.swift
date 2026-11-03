#if os(iOS)
import DesignSystemUI
import SwiftUI

/// The home's `NoticeBanner`s, one at a time: the next drops in once the last is gone and the
/// scene is in view (`TodayModel+Notices.swift`).
struct HomeNotices: ViewModifier {
    @Bindable var model: TodayModel

    func body(content: Content) -> some View {
        content
            .noticeBanner(item: $model.notice) { notice in banner(for: notice) }
            .onChange(of: model.notice == nil && model.step == .scene && !model.isBurstOpen) { _, free in
                if free { Task { await model.showNextNotice() } }
            }
    }

    /// Who moved the squad, over the new scene's badge.
    private func banner(for notice: TodayModel.Notice) -> some View {
        NoticeBanner(
            notice.picker.map { Text("\($0) 把小队搬到了\(notice.scene.name)", bundle: .module) }
                ?? Text("小队搬到了\(notice.scene.name)", bundle: .module)
        ) { SceneBadge(notice.scene) }
    }
}
#endif
