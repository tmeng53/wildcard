#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// The style guide's waits: 三拍 in a filled button on each accent, and beside a quiet action.
struct LoadingGuide: View {
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        GuideGroup(Text("等待：三拍，整页是两张票", bundle: .module)) {
            VStack(spacing: Space.xs) {
                Button {
                } label: {
                    Text("发布", bundle: .module).loadingLabel(true).frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                Button {
                } label: {
                    Text("发布", bundle: .module).loadingLabel(true).frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .accentTone(.brand)
                HStack(spacing: Space.xs) {
                    LoadingDots(delay: 0)
                    Text("换一组", bundle: .module)
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(Color(role: .fgSubtle, in: theme))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("styleguide.loading")
    }
}
#endif
