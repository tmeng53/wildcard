#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// The design system on one screen, foundations first, then every shared component: the app
/// shows it with `-styleguide`, and CI screenshots it in each scene so a change to a token or a
/// component is visible in review. The scene bar at the top recolors everything.
public struct StyleGuideView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var theme: SceneTheme = .pool

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxl) {
                ColorSection()
                TypeSection()
                LayoutSection()
                ButtonSection()
                PickSection()
                ScenePickGuide()
                KindSection()
                StatusSection()
                ListSection()
                StageSection()
                MotionSection()
            }
            .padding(.horizontal, Space.pageMargin)
            .padding(.top, Space.headerGap)
            .padding(.bottom, Space.xxl)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            CategoryBar(
                SceneTheme.allCases.map {
                    CategoryBarItem(id: $0, title: $0.name, accessibilityIdentifier: "styleguide.scene.\($0.rawValue)")
                }, selection: $theme, isPinned: true
            )
        }
        .background(Color(role: .bgCanvas, in: theme).ignoresSafeArea())
        .environment(\.sceneTheme, theme)
        .animation(.wildcard(Motion.page, reduceMotion: reduceMotion), value: theme)
    }
}

// MARK: - Shared

/// A section's number and title, like the design canvas's boards.
struct SectionTitle: View {
    @Environment(\.sceneTheme) private var theme
    let number: Int
    let title: Text

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Text(verbatim: "\(number)")
                .typeStyle(TypeRamp.scoreCard)
                .foregroundStyle(Color(role: .fgAccent, in: theme))
            title
                .typeStyle(TypeRamp.title)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("styleguide.section.\(number)")
    }
}

/// A group inside a section: a label, then what it shows.
struct GuideGroup<Content: View>: View {
    let label: Text
    let content: Content

    init(_ label: Text, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.labelGap) {
            SectionLabel(label)
            content
        }
    }
}

/// A token's code name: for developers, so it is not translated.
struct TokenName: View {
    @Environment(\.sceneTheme) private var theme
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(Color(role: .fgMuted, in: theme))
    }
}

#Preview {
    StyleGuideView()
}
#endif
