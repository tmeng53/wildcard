#if os(iOS)
import DesignSystem
import DesignSystemUI
import MeDomain
import SwiftUI

/// 注销账号: what goes, one plain sentence a line, then the way out. 先不注销 is the big ink
/// button, since most who come here change their mind; confirming with Apple is the small
/// outlined one under it.
struct DeleteAccountView: View {
    @Bindable var model: MeModel
    let close: () -> Void
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeaderButton(Text("返回", bundle: .module), systemImage: "chevron.left", action: close)
                .disabled(model.deletion == .deleting)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    MeStage(character: model.overview?.character, mood: .teary, size: CGSize(width: 96, height: 120))
                        .frame(maxWidth: .infinity)
                    Text("注销账号", bundle: .module)
                        .typeStyle(TypeRamp.title)
                        .foregroundStyle(Color(role: .fgDefault, in: theme))
                        .padding(.top, Space.l)
                        .padding(.bottom, Space.xs)
                    line(Text("外卡运动员、昵称和口头禅会删掉", bundle: .module))
                    line(Text("所有打卡、照片和请假条会删掉", bundle: .module))
                    if let squadName = model.overview?.squadName {
                        line(Text("你会离开\(squadName)", bundle: .module))
                    }
                    line(Text("给 AI 的同意也一起撤回", bundle: .module))
                    Text("删了就找不回来了。", bundle: .module)
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                        .padding(.top, Space.s)
                }
                .padding(.top, Space.xs)
                .padding(.bottom, Space.l)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            buttons
        }
        .padding(.horizontal, Space.pageMargin)
        .padding(.top, Space.xs)
        .padding(.bottom, Space.l)
        .background(Color(role: .bgCanvas, in: theme))
        // A container, so the page's identifier doesn't replace its buttons' own.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("delete.page")
    }

    private var buttons: some View {
        VStack(spacing: Space.s) {
            if case .failed(let error) = model.deletion {
                Group {
                    if error == .confirmationFailed {
                        Text("Apple 那边没确认上，再试一次", bundle: .module)
                    } else {
                        Text("网络开小差了，再试一次", bundle: .module)
                    }
                }
                .typeStyle(TypeRamp.footnote)
                .foregroundStyle(Color(role: .fgMuted, in: theme))
                .accessibilityIdentifier("delete.failed")
            }
            Button(action: close) {
                Text("先不注销", bundle: .module).frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.deletion == .deleting)
            .accessibilityIdentifier("delete.cancel")
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
            }
            .buttonStyle(AppleButtonStyle(.outlined))
            .disabled(!model.deletion.canConfirm)
            .accessibilityIdentifier("delete.confirm")
        }
        .frame(maxWidth: .infinity)
    }

    /// One thing that goes, on its own line over a hairline.
    private func line(_ text: Text) -> some View {
        text
            .typeStyle(TypeRamp.body)
            .foregroundStyle(Color(role: .fgDefault, in: theme))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Space.m)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color(role: .borderDefault, in: theme))
                    .frame(height: Sizing.hairline)
            }
    }
}
#endif
