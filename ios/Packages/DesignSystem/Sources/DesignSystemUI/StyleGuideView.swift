#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// Every token on one screen: the app shows it until the first feature screen lands, and CI
/// screenshots it in each scene so a change to a token is visible in review.
public struct StyleGuideView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var theme: SceneTheme = .pool

    public init() {}

    public var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SceneStage(theme: $theme)
                    VStack(alignment: .leading, spacing: Space.xxl) {
                        ColorSection()
                        TypeSection()
                        MotionSection()
                        ChoiceSection()
                    }
                    .padding(.horizontal, Space.gutter)
                    .padding(.top, Space.xl)
                    .padding(.bottom, Space.xxl)
                }
            }
            // Unclipped, so the scene's wash reaches behind the status bar and into the top overscroll.
            .scrollClipDisabled()
            // A frosted band behind the status bar, so scrolled text never runs into the clock.
            // The root reader knows the status bar's height; an overlay alone gets no safe area.
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(.thickMaterial)
                    .frame(height: proxy.safeAreaInsets.top)
                    .offset(y: -proxy.safeAreaInsets.top)
                    .allowsHitTesting(false)
            }
        }
        .background(Color(role: .canvas, in: theme).ignoresSafeArea())
        .environment(\.sceneTheme, theme)
        .animation(.wildcard(Motion.smooth, reduceMotion: reduceMotion), value: theme)
    }
}

// MARK: - Shared

struct SectionTitle: View {
    @Environment(\.sceneTheme) private var theme
    let number: Int
    let title: Text

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Text(verbatim: String(format: "%02d", number))
                .typeStyle(TypeRamp.scoreMedium)
                .foregroundStyle(Color(role: .signatureText, in: theme))
            title
                .typeStyle(TypeRamp.title)
                .foregroundStyle(Color(role: .textPrimary, in: theme))
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    StyleGuideView()
}
#endif
