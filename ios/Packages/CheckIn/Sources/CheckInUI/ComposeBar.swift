#if os(iOS)
import DesignSystem
import DesignSystemUI
import SwiftUI

/// The top of every page a member writes a post on (发动态, 请假条): 取消 on the left, the
/// page's name in the middle and the glass 发布 (or 保存) that finishes it on the right.
struct ComposeBar: View {
    @Environment(\.sceneTheme) private var theme
    let title: Text
    let finish: Text
    let isWorking: Bool
    let canFinish: Bool
    /// The buttons' UI-test identifiers.
    let cancelID: String
    let finishID: String
    let cancel: () -> Void
    let done: () -> Void

    var body: some View {
        HStack {
            HeaderTextButton(Text("取消", bundle: .module), action: cancel)
                .accessibilityIdentifier(cancelID)
            Spacer()
            HeaderTextButton(finish, prominent: true, isWorking: isWorking, action: done)
                .disabled(!canFinish)
                .accessibilityIdentifier(finishID)
        }
        .overlay {
            title
                .typeStyle(TypeRamp.headline)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.horizontal, Space.pageMargin)
        .padding(.vertical, Space.xxs)
    }
}
#endif
