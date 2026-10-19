#if os(iOS)
import DesignSystem
import DesignSystemUI
import SwiftUI

/// What the author alone sees when the reason reads as self-harm (spec section 3): no joke, a
/// gentle line, and the 988 line to call or text. Teammates see nothing.
struct CareLine: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.openURL) private var openURL

    var body: some View {
        // Every line of the care copy shows in full, even with the keyboard up: none of it may
        // be cut to an ellipsis.
        VStack(alignment: .leading, spacing: Space.s) {
            Text("这条先不写段子了。最近要是真的很难，找个人聊聊吧。", bundle: .module)
                .typeStyle(TypeRamp.callout)
                .foregroundStyle(Color(role: .textPrimary, in: theme))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Sizing.pillGap) {
                ChoicePill(Text("打给 988", bundle: .module), systemImage: "phone", isSelected: false) {
                    open("tel:988")
                }
                .accessibilityIdentifier("disclaimer.care.call")
                ChoicePill(Text("发短信给 988", bundle: .module), systemImage: "message", isSelected: false) {
                    open("sms:988")
                }
                .accessibilityIdentifier("disclaimer.care.text")
            }
            Text("美国和加拿大都能拨 988，24 小时，免费。美国的线路可以要中文翻译。", bundle: .module)
                .typeStyle(TypeRamp.caption)
                .foregroundStyle(Color(role: .textSecondary, in: theme))
                .fixedSize(horizontal: false, vertical: true)
            Text("有紧急危险请直接打 911。", bundle: .module)
                .typeStyle(TypeRamp.caption)
                .foregroundStyle(Color(role: .textSecondary, in: theme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("disclaimer.care")
    }

    private func open(_ address: String) {
        guard let url = URL(string: address) else { return }
        openURL(url)
    }
}
#endif
