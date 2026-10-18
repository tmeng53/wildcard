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

// MARK: - Names and roles the style guide shows

extension SceneTheme {
    var name: Text {
        switch self {
        case .pool: Text("游泳池", bundle: .module)
        case .track: Text("跑道", bundle: .module)
        case .gym: Text("健身房", bundle: .module)
        case .tennis: Text("网球场", bundle: .module)
        case .climbing: Text("攀岩馆", bundle: .module)
        }
    }
}

extension Meaning {
    /// The short label on a check-in capsule.
    var capsuleLabel: Text {
        switch self {
        case .trained: Text("练了", bundle: .module)
        case .fresh: Text("健康餐", bundle: .module)
        case .indulgence: Text("放纵餐", bundle: .module)
        case .disclaimer: Text("免责", bundle: .module)
        }
    }

    /// The full name, for tags.
    var fullName: Text {
        switch self {
        case .trained: Text("练了", bundle: .module)
        case .fresh: Text("健康餐", bundle: .module)
        case .indulgence: Text("坦白放纵餐", bundle: .module)
        case .disclaimer: Text("今日免责声明", bundle: .module)
        }
    }

    var symbol: String {
        switch self {
        case .trained: "dumbbell.fill"
        case .fresh: "leaf.fill"
        case .indulgence: "birthday.cake.fill"
        case .disclaimer: "moon.stars.fill"
        }
    }

    var tint: ColorRole {
        switch self {
        case .trained: .meaningTrained
        case .fresh: .meaningFresh
        case .indulgence: .meaningIndulgence
        case .disclaimer: .meaningDisclaimer
        }
    }

    var ink: ColorRole {
        switch self {
        case .trained: .meaningTrainedInk
        case .fresh: .meaningFreshInk
        case .indulgence: .meaningIndulgenceInk
        case .disclaimer: .meaningDisclaimerInk
        }
    }

    var wash: ColorRole {
        switch self {
        case .trained: .meaningTrainedWash
        case .fresh: .meaningFreshWash
        case .indulgence: .meaningIndulgenceWash
        case .disclaimer: .meaningDisclaimerWash
        }
    }

    var text: ColorRole {
        switch self {
        case .trained: .meaningTrainedText
        case .fresh: .meaningFreshText
        case .indulgence: .meaningIndulgenceText
        case .disclaimer: .meaningDisclaimerText
        }
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

/// A score like `18/25`: the count in signature text, the goal smaller in tertiary ink.
struct Score: View {
    @Environment(\.sceneTheme) private var theme
    let count: Int
    let goal: Int
    let countStyle: TypeStyle
    let goalStyle: TypeStyle

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(verbatim: "\(count)")
                .typeStyle(countStyle)
                .foregroundStyle(Color(role: .signatureText, in: theme))
            Text(verbatim: "/\(goal)")
                .typeStyle(goalStyle)
                .foregroundStyle(Color(role: .textTertiary, in: theme))
        }
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(count)/\(goal)"))
    }
}

#Preview {
    StyleGuideView()
}
#endif
