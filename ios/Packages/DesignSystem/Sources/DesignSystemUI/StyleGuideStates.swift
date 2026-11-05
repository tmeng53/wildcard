#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// Buttons that float (a header's words, actions over art): interactive Liquid Glass, the
/// prominent and primary ones tinted.
struct FloatingGuide: View {
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        GuideGroup(Text("浮着的按钮：液态玻璃", bundle: .module)) {
            VStack(spacing: Space.s) {
                HStack {
                    HeaderTextButton(Text("取消", bundle: .module)) {}
                    Spacer()
                    HeaderTextButton(Text("发布", bundle: .module), prominent: true) {}
                }
                bottomActions
            }
        }
    }

    private var bottomActions: some View {
        HStack(spacing: Space.xs) {
            Button {
            } label: {
                Text("再看一遍", bundle: .module).frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            Button {
            } label: {
                Text("存图", bundle: .module)
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .controlPlacement(.floating)
        .padding(Space.s)
        .background(
            Color(role: .bgScene, in: theme),
            in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}

/// The one offline state and the line under a change that didn't save.
struct StateGuide: View {
    var body: some View {
        GuideGroup(Text("空状态和出错", bundle: .module)) {
            VStack(spacing: Space.m) {
                StateView.offline(retryIdentifier: "styleguide.retry", retry: {})
                InlineFailure()
            }
        }
    }
}
#endif
