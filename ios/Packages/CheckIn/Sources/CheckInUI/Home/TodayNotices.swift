#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import SwiftUI

extension View {
    /// The `NoticeBanner`s `model` tells, one at a time over whatever page is open: the next drops
    /// in once the last is gone (`TodayModel+Notices.swift`). The app puts it over its tabs.
    public func todayNotices(_ model: TodayModel) -> some View {
        modifier(TodayNotices(model: model))
    }
}

private struct TodayNotices: ViewModifier {
    @Bindable var model: TodayModel
    private var unlocks: UnlockNotices? { model.unlockNotices }

    func body(content: Content) -> some View {
        content
            .noticeBanner(item: $model.notice, hold: model.hold, onTap: tap) { notice in
                // An edge under it for each still to come, at most two.
                banner(for: notice)
                    .noticesWaiting(model.waitingNotices)
                    .environment(\.sceneTheme, model.scene)
            }
            // Only an unlock: something the member earned arrives.
            .haptic(.appear, trigger: model.notice?.id) { _, id in id != nil && isUnlock(model.notice) }
            .onChange(of: model.isFreeForNotices, initial: true) { _, free in
                if free { Task { await model.showNextNotice() } }
            }
            // A celebration waiting for 今天.
            .onChange(of: model.isHomeInFront) { _, front in
                if front { Task { await model.showNextNotice() } }
            }
            // A 练了 that opened something, or one the last load found: told once each.
            .onChange(of: model.store.unlocked.count, initial: true) { _, count in
                if count > 0 { model.tellUnlocks() }
            }
            // A late post the server refused: told once, with a button to send it again.
            .onChange(of: model.store.refused.count, initial: true) { _, count in
                if count > 0 { model.tellRefused() }
            }
    }

    @ViewBuilder
    private func banner(for notice: TodayModel.Notice) -> some View {
        switch notice.news {
        case .moved(let scene, let picker):
            // Who moved the squad, over the new scene's badge.
            NoticeBanner(
                picker.map { Text("\($0) 把小队搬到了\(scene.name)", bundle: .module) }
                    ?? Text("小队搬到了\(scene.name)", bundle: .module),
                action: Text("去看看", bundle: .module)
            ) { SceneBadge(scene) }
        case .unlocked(let unlock):
            if let unlocks { unlocks.banner(unlock) }
        case .broadcast(let broadcast):
            let language = [AppLanguage.current.rawValue]
            NoticeBanner(
                Text(verbatim: broadcast.title.localized(in: language)),
                detail: broadcast.body.map { Text(verbatim: $0.localized(in: language)) },
                action: broadcast.action.map { Text(verbatim: $0.label.localized(in: language)) }
                    ?? Text("查看", bundle: .module)
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
        case .sendFailed(let canResend):
            NoticeBanner(
                model.failed.count == 1
                    ? Text("有一条发送失败", bundle: .module)
                    : Text("有 \(model.failed.count) 条发送失败", bundle: .module),
                detail: sendFailedDetail(canResend: canResend),
                action: canResend ? Text("重发", bundle: .module) : Text("知道了", bundle: .module)
            ) { NoticeSymbol(systemImage: "arrow.clockwise", tone: .brand) }
        case .more:
            NoticeBanner(Text("还有新通知", bundle: .module), action: Text("查看", bundle: .module)) {
                NoticeSymbol(systemImage: "bell.fill", tone: .brand)
            }
        case .told(let told):
            model.toldBanner?(told)
        }
    }

    private func sendFailedDetail(canResend: Bool) -> Text {
        guard canResend else { return Text("没能发出去", bundle: .module) }
        let failed = model.failed
        if failed.count > 1 { return Text("先重发最早的一条", bundle: .module) }
        if let line = failed.first?.draft.line, !line.isEmpty {
            return Text("「\(line)」没能发出去，改一下再试试", bundle: .module)
        }
        return Text("改一下再试试", bundle: .module)
    }

    private func tap(_ notice: TodayModel.Notice) {
        switch notice.news {
        case .unlocked(let unlock): unlocks?.open(unlock)
        case .broadcast(let broadcast):
            model.broadcastOpened?(broadcast)
            model.openDestination?(broadcast.action?.destination ?? .notices)
        case .goalSuggestion: model.openDestination?(.squad)
        case .sendFailed: model.resendFirst()
        case .more: model.openDestination?(.notices)
        case .moved: model.openDestination?(.today)
        case .told(let told): model.openDestination?(told.destination)
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
    let picture: (Unlock.Kind, String) -> AnyView

    /// - Parameters:
    ///   - banner: the `NoticeBanner` that says what opened.
    ///   - open: a tap on it: the editor, at that store or prop.
    ///   - badge: a store's sign or a piece's or prop's picture, as a broadcast's icon.
    ///   - picture: a piece or prop on its own, or a store's sign, filling its frame: a gift on a
    ///     broadcast's celebration card.
    public init<Banner: View, Badge: View, Picture: View>(
        banner: @escaping (Unlock) -> Banner, open: @escaping (Unlock) -> Void,
        badge: @escaping (Unlock.Kind, String) -> Badge, picture: @escaping (Unlock.Kind, String) -> Picture
    ) {
        self.banner = { AnyView(banner($0)) }
        self.open = open
        self.badge = { AnyView(badge($0, $1)) }
        self.picture = { AnyView(picture($0, $1)) }
    }
}
#endif
