#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// The primary action (打卡, 开跑, 完成): a solid signature capsule that shrinks while held.
/// The label brings its own type and horizontal padding; disabled, it turns a quiet grey.
public struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color(role: isEnabled ? .onSignature : .textTertiary, in: theme))
            .frame(minHeight: Sizing.checkInHeight)
            .background(Color(role: isEnabled ? .signature : .divider, in: theme), in: Capsule())
            .contentShape(Capsule())
            .modifier(PressFeedback(isPressed: configuration.isPressed))
    }
}
#endif
