#if os(iOS)
import DesignSystem
import DesignSystemUI
import HealthUI
import LocationDomain
import MeDomain
import SwiftUI
import UIKit

/// 设置: the member's character typing at its laptop, then a plain menu of hairline rows under
/// small group labels (偏好, 关于 with 意见反馈, 账号), with no icons, a chevron on each row that opens a page,
/// and an ink switch; 偏好's Apple 健康 and 桌面小组件 push their own pages, and 位置 asks for approximate location
/// once, then opens iOS Settings. Signing out and deleting the account come last. It holds only the app's
/// own settings: what belongs to the squad or the week lives with them (2026-11-02), and 球衣号码
/// with the character editor (2026-11-03).
struct SettingsView: View {
    @Bindable var model: MeModel
    let destinations: MeDestinations
    @State private var isSigningOut = false
    @State private var isPickingLanguage = false
    @State private var isHealthOpen = false
    @State private var isBirthdayOpen = false
    @State private var isWidgetGuideOpen = false
    @State private var isDemoAccountsOpen = false
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
            .navigationDestination(isPresented: $isBirthdayOpen) {
                BirthdayView(model: model)
            }
            .navigationDestination(isPresented: $isDemoAccountsOpen) {
                if let demoAccounts = destinations.admin.demoAccounts { DemoAccountsView(model: demoAccounts) }
            }
            .navigationDestination(isPresented: $isWidgetGuideOpen) {
                if let guide = destinations.widgetGuide { guide }
            }
            .navigationDestination(isPresented: $isHealthOpen) {
                if let health = destinations.health { HealthSettingsView(health: health) }
            }
            .navigationDestination(isPresented: feedbackOpen) {
                if let feedback = model.feedbackPage {
                    FeedbackView(
                        model: feedback, character: model.overview?.character, writeReview: destinations.writeReview
                    )
                    .pushedPage(canGoBack: feedback.phase != .sending, hidesTabBar: true)
                    .accentTone(.ink)
                }
            }
    }

    private var feedbackOpen: Binding<Bool> {
        Binding(get: { model.feedbackPage != nil }, set: { if !$0 { model.feedbackPage = nil } })
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
                if !destinations.admin.isEmpty {
                    adminGroup
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
            // The coach's own switch, under 通知: its pushes are silent, and 通知 keeps its words anyway.
            SwitchRow(
                Text(copy: "教练消息", bundle: .module),
                isOn: Binding(
                    get: { model.coachPushOn },
                    set: { isOn in Task { await model.setCoachPush(isOn) } })
            )
            .accessibilityIdentifier("me.coachNotifications")
            ListRow(
                Text(copy: "生日", bundle: .module),
                value: model.overview?.birthday.map { Text(verbatim: $0.dotted) } ?? Text(copy: "未填", bundle: .module)
            ) {
                isBirthdayOpen = true
            }
            .accessibilityIdentifier("me.birthday")
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
            if let location = destinations.location {
                ListRow(
                    Text(copy: "位置", bundle: .module),
                    value: location.access == .allowed
                        ? Text(copy: "已打开", bundle: .module) : Text(copy: "未打开", bundle: .module)
                ) {
                    // Only the first time can the app ask; after that, iOS Settings changes it.
                    if location.access == .notAsked {
                        Task { await location.ask() }
                    } else if let settings = URL(string: UIApplication.openSettingsURLString) {
                        openURL(settings)
                    }
                }
                .accessibilityIdentifier("me.location")
                .task { await location.refresh() }
            }
            if destinations.widgetGuide != nil {
                ListRow(Text(copy: "桌面小组件", bundle: .module)) {
                    isWidgetGuideOpen = true
                }
                .accessibilityIdentifier("me.widgets")
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

    /// Apple Weather's data sources, which WeatherKit asks apps that show its weather to link.
    private static let weatherSources = URL(string: "https://developer.apple.com/weatherkit/data-source-attribution/")
    private var aboutGroup: some View {
        MenuGroup(Text(copy: "关于", bundle: .module)) {
            // Also the app's 联系我们 (App Review 1.2): the page shows the support email too.
            ListRow(Text(copy: "意见反馈", bundle: .module)) {
                model.feedbackPage = FeedbackModel(service: model.feedback, app: .current, newID: UUID.init)
            }
            .accessibilityIdentifier("me.feedback")
            ListRow(Text(copy: "隐私政策", bundle: .module)) {
                openURL(destinations.privacyPolicy)
            }
            .accessibilityIdentifier("me.privacy")
            ListRow(Text(copy: "用户条款", bundle: .module)) {
                openURL(destinations.terms)
            }
            .accessibilityIdentifier("me.terms")
            // WeatherKit's terms: the coach's weather credits Apple Weather and links its sources.
            ListRow(Text(copy: "天气数据：Apple 天气", bundle: .module), showsDivider: false) {
                if let sources = Self.weatherSources { openURL(sources) }
            }
            .accessibilityIdentifier("me.weatherSources")
        }
    }

    /// Only for admins (and, for 演示账号, their demo accounts): tools to try the app as a
    /// newcomer would, and the demo accounts for promo pictures.
    private var adminGroup: some View {
        MenuGroup(Text(copy: "管理员", bundle: .module)) {
            if let previewSignUp = destinations.admin.previewSignUp {
                ListRow(
                    Text(copy: "预览注册", bundle: .module), showsDivider: destinations.admin.demoAccounts != nil,
                    action: previewSignUp
                )
                .accessibilityIdentifier("me.previewSignUp")
            }
            if destinations.admin.demoAccounts != nil {
                ListRow(Text(copy: "演示账号", bundle: .module), showsDivider: false) { isDemoAccountsOpen = true }
                    .accessibilityIdentifier("me.demoAccounts")
            }
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

extension FeedbackApp {
    /// This app on this phone: its version and build, iOS, the model (iPhone17,3) and the
    /// language picked in the app.
    @MainActor static var current: FeedbackApp {
        let info = Bundle.main.infoDictionary ?? [:]
        var system = utsname()
        uname(&system)
        let machine = withUnsafeBytes(of: &system.machine) { bytes in
            String(bytes: bytes.prefix { $0 != 0 }, encoding: .utf8) ?? ""
        }
        return FeedbackApp(
            appVersion: info["CFBundleShortVersionString"] as? String ?? "?",
            build: info["CFBundleVersion"] as? String ?? "?",
            system: "iOS \(UIDevice.current.systemVersion)",
            device: machine.isEmpty ? UIDevice.current.model : machine,
            language: AppLanguage.current.rawValue)
    }
}
#endif
