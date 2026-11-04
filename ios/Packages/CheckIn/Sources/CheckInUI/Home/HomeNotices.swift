#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import SwiftUI

/// The home's `NoticeBanner`s, one at a time: the next drops in once the last is gone and the
/// scene is in view (`TodayModel+Notices.swift`).
struct HomeNotices: ViewModifier {
    @Bindable var model: TodayModel
    private var unlocks: UnlockNotices? { model.unlockNotices }

    func body(content: Content) -> some View {
        content
            .noticeBanner(item: $model.notice, hold: model.hold, onTap: tap) { notice in banner(for: notice) }
            // Only an unlock: something the member earned arrives.
            .haptic(.appear, trigger: model.notice?.id) { _, id in id != nil && isUnlock(model.notice) }
            .onChange(of: model.notice == nil && model.step == .scene && !model.isBurstOpen) { _, free in
                if free { Task { await model.showNextNotice() } }
            }
            // A 练了 that opened something, or one the last load found: told once each.
            .onChange(of: model.store.unlocked.count, initial: true) { _, count in
                if count > 0 { model.tellUnlocks() }
            }
    }

    @ViewBuilder
    private func banner(for notice: TodayModel.Notice) -> some View {
        switch notice.news {
        case .moved(let scene, let picker):
            // Who moved the squad, over the new scene's badge.
            NoticeBanner(
                picker.map { Text("\($0) 把小队搬到了\(scene.name)", bundle: .module) }
                    ?? Text("小队搬到了\(scene.name)", bundle: .module)
            ) { SceneBadge(scene) }
        case .unlocked(let unlock):
            if let unlocks { unlocks.banner(unlock) }
        case .broadcast(let broadcast):
            let language = [AppLanguage.current.rawValue]
            NoticeBanner(
                Text(verbatim: broadcast.title.localized(in: language)),
                detail: broadcast.body.map { Text(verbatim: $0.localized(in: language)) },
                action: broadcast.action.map { Text(verbatim: $0.label.localized(in: language)) }
            ) { NoticeSymbol(systemImage: "sparkles") }
        }
    }

    private func tap(_ notice: TodayModel.Notice) {
        switch notice.news {
        case .unlocked(let unlock): unlocks?.open(unlock)
        case .broadcast(let broadcast):
            if let action = broadcast.action { model.openDestination?(action.destination) }
        case .moved: break
        }
    }

    private func isUnlock(_ notice: TodayModel.Notice?) -> Bool {
        if case .unlocked = notice?.news { true } else { false }
    }
}

/// How the home tells a store or prop the member unlocked, from the app, which knows the
/// character editor's words for them and opens it on a tap (`TodayModel.tellUnlocks(with:)`).
public struct UnlockNotices {
    let banner: (Unlock) -> AnyView
    let open: (Unlock) -> Void

    /// - Parameters:
    ///   - banner: the `NoticeBanner` that says what opened.
    ///   - open: a tap on it: the editor, at that store or prop.
    public init<Banner: View>(banner: @escaping (Unlock) -> Banner, open: @escaping (Unlock) -> Void) {
        self.banner = { AnyView(banner($0)) }
        self.open = open
    }
}
#endif
