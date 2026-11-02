#if os(iOS)
import DesignSystem
import DesignSystemUI
import MeDomain
import SwiftUI

/// 设置: the member's character typing at its laptop, then a plain menu of hairline rows under
/// small group labels (偏好, 关于, 账号), with no icons, a chevron on each row that opens a page,
/// and an ink switch. Signing out and deleting the account come last. It holds only the app's
/// own settings: what belongs to the squad or the week lives with them (2026-11-02). 球衣号码
/// stays here until its place on the card is decided.
struct SettingsView: View {
    @Bindable var model: MeModel
    let destinations: MeDestinations
    let close: () -> Void
    @State private var isSigningOut = false
    @State private var isPickingNumber = false
    @State private var isPickingLanguage = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        ZStack {
            if isPickingNumber {
                JerseyNumberView(model: model) { isPickingNumber = false }
                    .swipesBack { isPickingNumber = false }
                    .transition(.move(edge: .trailing))
            } else {
                menu.swipesBack(perform: close)
            }
        }
        .animation(.wildcard(Motion.page, reduceMotion: reduceMotion), value: isPickingNumber)
    }

    private var menu: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HeaderButton(Text("返回", bundle: .module), systemImage: "chevron.left", action: close)
                    .accessibilityIdentifier("settings.back")
                // The character types beside the heading, standing on its line, so the menu starts
                // right under it.
                HStack(alignment: .bottom, spacing: Space.s) {
                    Text("设置", bundle: .module)
                        .typeStyle(TypeRamp.largeTitle)
                        .foregroundStyle(Color(role: .fgDefault, in: theme))
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    MeStage(character: model.overview?.character, mood: .typing, size: CGSize(width: 72, height: 90))
                        .accessibilityHidden(true)
                }
                .padding(.top, Space.s)
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
        // Always scrollable: the room left for the tab bar is a safe-area inset, which a size-based
        // bounce doesn't count, so the last rows could fit the page yet sit under the bar.
        .scrollIndicators(.hidden)
        .background(Color(role: .bgCanvas, in: theme))
        .accessibilityIdentifier("settings.page")
    }

    private var preferencesGroup: some View {
        MenuGroup(Text("偏好", bundle: .module)) {
            ListRow(
                Text("球衣号码", bundle: .module), value: Text(verbatim: model.overview?.cardNumber?.text ?? "")
            ) {
                isPickingNumber = true
            }
            .accessibilityIdentifier("me.jerseyNumber")
            SwitchRow(
                Text("通知", bundle: .module),
                isOn: Binding(
                    get: { model.dailyPushOn },
                    set: { isOn in Task { await model.setDailyPush(isOn) } })
            )
            .accessibilityIdentifier("me.notifications")
            ListRow(
                Text("语言", bundle: .module), value: Text(verbatim: AppLanguage.current.name), showsDivider: false
            ) {
                isPickingLanguage = true
            }
            .accessibilityIdentifier("me.language")
            .languagePicker(isPresented: $isPickingLanguage)
        }
    }

    private var aboutGroup: some View {
        MenuGroup(Text("关于", bundle: .module)) {
            ListRow(Text("隐私政策", bundle: .module)) {
                openURL(destinations.privacyPolicy)
            }
            .accessibilityIdentifier("me.privacy")
            ListRow(Text("用户条款", bundle: .module), showsDivider: false) {
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
            ListRow(Text("注销账号", bundle: .module), showsDivider: false) {
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
