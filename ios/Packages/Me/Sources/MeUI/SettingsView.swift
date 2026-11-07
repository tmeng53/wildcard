#if os(iOS)
import DesignSystem
import DesignSystemUI
import HealthUI
import MeDomain
import SwiftUI

/// 设置: the member's character typing at its laptop, then a plain menu of hairline rows under
/// small group labels (偏好, 关于, 账号), with no icons, a chevron on each row that opens a page,
/// and an ink switch; 偏好's Apple 健康 pushes its own page. Signing out and deleting the account come last. It holds only the app's
/// own settings: what belongs to the squad or the week lives with them (2026-11-02), and 球衣号码
/// with the character editor (2026-11-03).
struct SettingsView: View {
    @Bindable var model: MeModel
    let destinations: MeDestinations
    @State private var isSigningOut = false
    @State private var isPickingLanguage = false
    @State private var isHealthOpen = false
    @Environment(\.openURL) private var openURL
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        menu
            .pushedPage()
            // 注销账号, pushed over 设置; its back button and swipe wait while the account is deleting.
            .navigationDestination(isPresented: deletionOpen) {
                DeleteAccountView(model: model) { model.closeDeletion() }
                    .pushedPage(canGoBack: model.deletion != .deleting, hidesTabBar: true)
                    .accentTone(.ink)
            }
            .navigationDestination(isPresented: $isHealthOpen) {
                if let health = destinations.health { HealthSettingsView(health: health) }
            }
    }

    /// 注销账号 is open; the system's back closes it as 先不注销 does.
    private var deletionOpen: Binding<Bool> {
        Binding(get: { model.isDeletionOpen }, set: { if !$0 { model.closeDeletion() } })
    }

    private var menu: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // The character types beside the heading, standing on its line, so the menu starts
                // right under it.
                HStack(alignment: .bottom, spacing: Space.s) {
                    Text(copy: "设置", bundle: .module)
                        .typeStyle(TypeRamp.largeTitle)
                        .foregroundStyle(Color(role: .fgDefault, in: theme))
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    MeStage(character: model.overview?.character, mood: .typing, size: CGSize(width: 72, height: 90))
                        .accessibilityHidden(true)
                }
                preferencesGroup
                aboutGroup
                if let previewSignUp = destinations.previewSignUp {
                    adminGroup(previewSignUp)
                }
                accountGroup
                if model.saveFailed {
                    SaveFailed().padding(.top, Space.m)
                }
            }
            .padding(.horizontal, Space.pageMargin)
            .padding(.top, Space.xs)
            .padding(.bottom, Space.l)
        }
        // Always scrollable: the room left for the tab bar is a safe-area inset, which a size-based
        // bounce doesn't count, so the last rows could fit the page yet sit under the bar.
        .scrollIndicators(.hidden)
        .barTitleOnScroll(Text(copy: "设置", bundle: .module))
        .background(Color(role: .bgCanvas, in: theme))
        .accessibilityIdentifier("settings.page")
    }

    private var preferencesGroup: some View {
        MenuGroup(Text(copy: "偏好", bundle: .module)) {
            SwitchRow(
                Text(copy: "通知", bundle: .module),
                isOn: Binding(
                    get: { model.dailyPushOn },
                    set: { isOn in Task { await model.setDailyPush(isOn) } })
            )
            .accessibilityIdentifier("me.notifications")
            // The coach's own switch, under 通知: silent pushes, and 通知 keeps its words anyway.
            SwitchRow(
                Text(copy: "教练消息", bundle: .module),
                detail: Text(copy: "教练的消息和回复，静默推送。关掉后通知里照样有。", bundle: .module),
                isOn: Binding(
                    get: { model.coachPushOn },
                    set: { isOn in Task { await model.setCoachPush(isOn) } })
            )
            .accessibilityIdentifier("me.coachNotifications")
            if let health = destinations.health, health.isAvailable {
                ListRow(
                    Text(copy: "Apple 健康", bundle: .module),
                    value: health.isConnected ? Text(copy: "已连接", bundle: .module) : Text(copy: "未连接", bundle: .module)
                ) {
                    isHealthOpen = true
                }
                .accessibilityIdentifier("me.health")
                .task { await health.refresh() }
            }
            ListRow(
                Text(copy: "语言", bundle: .module), value: Text(verbatim: AppLanguage.current.name), showsDivider: false
            ) {
                isPickingLanguage = true
            }
            .accessibilityIdentifier("me.language")
            .languagePicker(isPresented: $isPickingLanguage)
        }
    }

    private var aboutGroup: some View {
        MenuGroup(Text(copy: "关于", bundle: .module)) {
            ListRow(Text(copy: "隐私政策", bundle: .module)) {
                openURL(destinations.privacyPolicy)
            }
            .accessibilityIdentifier("me.privacy")
            ListRow(Text(copy: "用户条款", bundle: .module), showsDivider: false) {
                openURL(destinations.terms)
            }
            .accessibilityIdentifier("me.terms")
        }
    }

    /// Only for admins: tools to try the app as a newcomer would.
    private func adminGroup(_ previewSignUp: @escaping () -> Void) -> some View {
        MenuGroup(Text(copy: "管理员", bundle: .module)) {
            ListRow(Text(copy: "预览注册", bundle: .module), showsDivider: false, action: previewSignUp)
                .accessibilityIdentifier("me.previewSignUp")
        }
    }

    private var accountGroup: some View {
        MenuGroup(Text(copy: "账号", bundle: .module)) {
            ListRow(Text(copy: "退出登录", bundle: .module), showsChevron: false) {
                isSigningOut = true
            }
            .accessibilityIdentifier("me.signOut")
            // Signing out asks once, in the app's glass menu, from the row itself.
            .glassConfirm(
                isPresented: $isSigningOut,
                GlassMenuItem(
                    Text(copy: "退出登录", bundle: .module), systemImage: "rectangle.portrait.and.arrow.right",
                    role: .destructive, id: "me.signOut.menu",
                    confirm: .init(
                        Text(copy: "退出登录？", bundle: .module), label: Text(copy: "退出登录", bundle: .module),
                        id: "me.signOut.confirm")
                ) {
                    Task { await model.signOut() }
                }
            )
            ListRow(Text(copy: "注销账号", bundle: .module), showsDivider: false) {
                model.openDeletion()
            }
            .accessibilityIdentifier("me.deleteAccount")
        }
    }
}

/// A group of the menu: its small label, then its rows straight on the page.
private struct MenuGroup<Rows: View>: View {
    private let title: Text
    private let rows: Rows

    init(_ title: Text, @ViewBuilder rows: () -> Rows) {
        self.title = title
        self.rows = rows()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            SectionLabel(title)
            VStack(spacing: 0) { rows }
        }
        .padding(.top, Space.l)
    }
}
#endif
