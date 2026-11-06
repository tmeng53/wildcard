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
            .noticeBanner(item: $model.notice, hold: model.hold, onTap: tap) { notice in
                // An edge under it for each still to come, at most two.
                banner(for: notice).noticesWaiting(model.waitingNotices)
            }
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
            ) {
                if let icon = broadcast.icon, let unlocks {
                    unlocks.badge(icon.kind, icon.id)
                } else {
                    NoticeSymbol(systemImage: "sparkles")
                }
            }
        case .goalSuggestion(let suggestion):
            NoticeBanner(
                Text("连续 \(suggestion.weeks) 周超过小队目标", bundle: .module),
                detail: Text("改成人均 \(suggestion.daysPerMember) 天？", bundle: .module),
                action: Text("去改目标", bundle: .module)
            ) { NoticeSymbol(systemImage: "chart.line.uptrend.xyaxis") }
        case .more:
            NoticeBanner(Text("还有新通知 · 去看看", bundle: .module), showsChevron: true) {
                NoticeSymbol(systemImage: "bell.fill")
            }
        }
    }

    private func tap(_ notice: TodayModel.Notice) {
        switch notice.news {
        case .unlocked(let unlock): unlocks?.open(unlock)
        case .broadcast(let broadcast):
            if let action = broadcast.action {
                model.broadcastOpened?(broadcast)
                model.openDestination?(action.destination)
            }
        case .goalSuggestion: model.openDestination?(.squad)
        case .more: model.openDestination?(.notices)
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
    let badge: (Unlock.Kind, String) -> AnyView

    /// - Parameters:
    ///   - banner: the `NoticeBanner` that says what opened.
    ///   - open: a tap on it: the editor, at that store or prop.
    ///   - badge: a store's sign or a piece's or prop's picture, as a broadcast's icon.
    public init<Banner: View, Badge: View>(
        banner: @escaping (Unlock) -> Banner, open: @escaping (Unlock) -> Void,
        badge: @escaping (Unlock.Kind, String) -> Badge
    ) {
        self.banner = { AnyView(banner($0)) }
        self.open = open
        self.badge = { AnyView(badge($0, $1)) }
    }
}
#endif
