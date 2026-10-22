#if canImport(SwiftUI)
import DesignSystem
import DesignSystemUI
import MeDomain
import SwiftUI

/// 注销账号: what goes, said plainly, then one confirmation with Apple. The member came here on
/// purpose, so the confirm button is the page's one strong action; 先不注销 goes back.
struct DeleteAccountView: View {
    @Bindable var model: MeModel
    let close: () -> Void
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            HeaderButton(Text("返回", bundle: .module), systemImage: "chevron.left", action: close)
                .disabled(model.deletion == .deleting)
            MeStage(character: model.overview?.character)
                .scaleEffect(0.7)
                .frame(maxWidth: .infinity)
                .frame(height: MeStage.size.height * 0.7)
            VStack(alignment: .leading, spacing: Space.m) {
                Text("注销账号", bundle: .module)
                    .typeStyle(TypeRamp.title)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                VStack(alignment: .leading, spacing: Space.s) {
                    line("person", Text("角色、昵称和口头禅会删掉", bundle: .module))
                    line("photo", Text("所有打卡、照片和请假条会删掉", bundle: .module))
                    if let squadName = model.overview?.squadName {
                        line("person.2", Text("你会离开\(squadName)", bundle: .module))
                    }
                    line("sparkles", Text("给 AI 的同意也一起撤回", bundle: .module))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
                Text("删了就找不回来了。", bundle: .module)
                    .typeStyle(TypeRamp.footnote)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
            }
            Spacer(minLength: 0)
            VStack(spacing: Space.xs) {
                if case .failed = model.deletion {
                    Text("网络开小差了，再试一次", bundle: .module)
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                        .accessibilityIdentifier("delete.failed")
                }
                Button {
                    Task { await model.deleteAccount() }
                } label: {
                    Label {
                        if model.deletion == .deleting {
                            Text("正在注销…", bundle: .module)
                        } else {
                            Text("用 Apple 确认注销", bundle: .module)
                        }
                    } icon: {
                        Image(systemName: "apple.logo")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(AppleButtonStyle())
                .disabled(!model.deletion.canConfirm)
                .accessibilityIdentifier("delete.confirm")
                Button(action: close) { Text("先不注销", bundle: .module) }
                    .buttonStyle(TextButtonStyle(.plain))
                    .disabled(model.deletion == .deleting)
                    .accessibilityIdentifier("delete.cancel")
            }
        }
        .padding(.horizontal, Space.pageMargin)
        .padding(.top, Space.xs)
        .padding(.bottom, Space.l)
        .background(Color(role: .bgCanvas, in: theme))
        // A container, so the page's identifier doesn't replace its buttons' own.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("delete.page")
    }

    private func line(_ systemImage: String, _ text: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Image(systemName: systemImage)
                .font(.system(size: Sizing.smallIcon + 2))
                .frame(width: Sizing.icon)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .accessibilityHidden(true)
            text
                .typeStyle(TypeRamp.body)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
        }
    }
}
#endif
