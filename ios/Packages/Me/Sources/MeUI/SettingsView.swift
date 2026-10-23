#if canImport(SwiftUI)
import DesignSystem
import DesignSystemUI
import MeDomain
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 设置: the member's character typing at its laptop, then a plain menu of hairline rows under
/// small group labels (小队, 偏好, 关于, 账号), with no icons and no chevrons, and an ink switch.
/// Signing out and deleting the account come last.
struct SettingsView: View {
    @Bindable var model: MeModel
    let destinations: MeDestinations
    let close: () -> Void
    @State private var isSigningOut = false
    @State private var isPickingNumber = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        ZStack {
            if isPickingNumber {
                JerseyNumberView(model: model) { isPickingNumber = false }
                    .transition(.move(edge: .trailing))
            } else {
                menu
            }
        }
        .animation(.wildcard(Motion.page, reduceMotion: reduceMotion), value: isPickingNumber)
    }

    private var menu: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HeaderButton(Text("返回", bundle: .module), systemImage: "chevron.left", action: close)
                    .accessibilityIdentifier("settings.back")
                MeStage(character: model.overview?.character, size: CGSize(width: 96, height: 120), mood: .typing)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
                Text("设置", bundle: .module)
                    .typeStyle(TypeRamp.largeTitle)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, Space.s)
                squadGroup
                preferencesGroup
                aboutGroup
                accountGroup
                if model.saveFailed {
                    SaveFailed().padding(.top, Space.m)
                }
            }
            .padding(.horizontal, Space.pageMargin)
            .padding(.top, Space.xs)
            .padding(.bottom, Space.l)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .background(Color(role: .bgCanvas, in: theme))
        .accessibilityIdentifier("settings.page")
    }

    private var squadGroup: some View {
        MenuGroup(Text("小队", bundle: .module)) {
            if let squad = model.overview?.squadName {
                ListRow(
                    Text("我的小队", bundle: .module), value: Text(squad), showsChevron: false, action: destinations.squad
                )
                .accessibilityIdentifier("me.squad")
            }
            ListRow(
                Text("球衣号码", bundle: .module), value: Text(verbatim: model.overview?.cardNumber?.text ?? ""),
                showsChevron: false
            ) {
                isPickingNumber = true
            }
            .accessibilityIdentifier("me.jerseyNumber")
            ListRow(
                Text("往期战报", bundle: .module), showsDivider: false, showsChevron: false, action: destinations.pastRecaps
            )
        }
    }

    private var preferencesGroup: some View {
        MenuGroup(Text("偏好", bundle: .module)) {
            SwitchRow(
                Text("通知", bundle: .module),
                isOn: Binding(
                    get: { model.dailyPushOn },
                    set: { isOn in Task { await model.setDailyPush(isOn) } })
            )
            .accessibilityIdentifier("me.notifications")
            ListRow(
                Text("语言", bundle: .module), value: Text("language.current", bundle: .module), showsDivider: false,
                showsChevron: false
            ) {
                // iOS keeps each app's language in Settings; the app follows it.
                if let settings = Self.appSettings { openURL(settings) }
            }
        }
    }

    private var aboutGroup: some View {
        MenuGroup(Text("关于", bundle: .module)) {
            ListRow(Text("隐私政策", bundle: .module), showsChevron: false) {
                openURL(destinations.privacyPolicy)
            }
            .accessibilityIdentifier("me.privacy")
            ListRow(Text("用户条款", bundle: .module), showsDivider: false, showsChevron: false) {
                openURL(destinations.terms)
            }
            .accessibilityIdentifier("me.terms")
        }
    }

    private var accountGroup: some View {
        MenuGroup(Text("账号", bundle: .module)) {
            ListRow(Text("退出登录", bundle: .module), showsChevron: false) {
                isSigningOut = true
            }
            .accessibilityIdentifier("me.signOut")
            // The system's own confirm, as the design asks: signing out is one tap from undoable.
            .confirmationDialog(Text("退出登录？", bundle: .module), isPresented: $isSigningOut, titleVisibility: .visible) {
                Button(role: .destructive) {
                    Task { await model.signOut() }
                } label: {
                    Text("退出登录", bundle: .module)
                }
                .accessibilityIdentifier("me.signOut.confirm")
            }
            ListRow(Text("注销账号", bundle: .module), showsDivider: false, showsChevron: false) {
                model.openDeletion()
            }
            .accessibilityIdentifier("me.deleteAccount")
        }
    }

    /// This app's page in the Settings app.
    @MainActor static var appSettings: URL? {
        #if canImport(UIKit)
        URL(string: UIApplication.openSettingsURLString)
        #else
        nil
        #endif
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
