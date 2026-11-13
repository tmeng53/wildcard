#if os(iOS)
import DesignSystem
import DesignSystemUI
import MeDomain
import SwiftUI

/// 设置 › 管理员 › 演示账号 (Tracy, 2026-11-13): the admin's own account, then the demo accounts
/// they made for promo pictures, by nickname, the one this phone is on marked 当前; a tap switches
/// to it, and 新建队员 makes one and switches to it, where it signs up like anyone.
struct DemoAccountsView: View {
    @Bindable var model: DemoAccountsModel
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s) {
                Text(copy: "演示账号", bundle: .module)
                    .typeStyle(TypeRamp.taskTitle)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 0) {
                    ForEach(model.accounts) { account in
                        ListRow(name(of: account), value: value(of: account), showsChevron: false) {
                            Task { await model.open(account) }
                        }
                        .accessibilityIdentifier("demoAccounts.account")
                    }
                    ListRow(
                        Text(copy: "新建队员", bundle: .module), systemImage: "plus",
                        value: model.phase == .switching(nil) ? Text(copy: "切换中", bundle: .module) : nil,
                        showsDivider: false, showsChevron: false
                    ) {
                        Task { await model.makeNew() }
                    }
                    .accessibilityIdentifier("demoAccounts.new")
                }
                .disabled(model.isSwitching)
                if model.phase == .failed { InlineFailure(Text(copy: "没切换成功", bundle: .module)) }
            }
            .padding(.horizontal, Space.pageMargin)
            .padding(.top, Space.xs)
            .padding(.bottom, Space.l)
        }
        .background(Color(role: .bgCanvas, in: theme))
        .pushedPage(canGoBack: !model.isSwitching)
        .task { await model.load() }
        .accessibilityIdentifier("demoAccounts.page")
    }

    private func name(of account: DemoAccount) -> Text {
        if account.isOwner { return Text(copy: "我的账号", bundle: .module) }
        guard let nickname = account.character?.nickname, !nickname.isEmpty else {
            return Text(copy: "未注册", bundle: .module)
        }
        return Text(verbatim: nickname)
    }

    private func value(of account: DemoAccount) -> Text? {
        if model.phase == .switching(account.id) { return Text(copy: "切换中", bundle: .module) }
        return account.id == model.current ? Text(copy: "当前", bundle: .module) : nil
    }
}
#endif
