#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// Names and symbols for scenes and check-in kinds, shared by the style guide and the screens.
extension SceneTheme {
    /// The scene's name (「第 42 周 · 跑道」).
    public var name: Text {
        switch self {
        case .pool: Text("游泳池", bundle: .module)
        case .track: Text("跑道", bundle: .module)
        case .gym: Text("健身房", bundle: .module)
        case .tennis: Text("网球场", bundle: .module)
        case .climbing: Text("攀岩馆", bundle: .module)
        }
    }
}

extension CheckInKind {
    /// The short label on a kind button or a check-in capsule.
    public var shortName: Text {
        switch self {
        case .trained: Text("练了", bundle: .module)
        case .healthyMeal: Text("健康餐", bundle: .module)
        case .cheatMeal: Text("放纵餐", bundle: .module)
        case .disclaimer: Text("请假", bundle: .module)
        }
    }

    /// The full name, for titles.
    public var fullName: Text {
        switch self {
        case .trained: Text("练了", bundle: .module)
        case .healthyMeal: Text("健康餐", bundle: .module)
        case .cheatMeal: Text("坦白放纵餐", bundle: .module)
        case .disclaimer: Text("今日请假条", bundle: .module)
        }
    }

    public var symbol: String {
        switch self {
        case .trained: "dumbbell.fill"
        case .healthyMeal: "leaf.fill"
        case .cheatMeal: "birthday.cake.fill"
        case .disclaimer: "moon.stars.fill"
        }
    }
}

/// A check-in kind as a round button with its word under it. The four kinds share the scene's
/// colors, so only the icon and the word tell them apart: the wash on white, white on the
/// scene's floor (the gym's are dark with volt). Unavailable, it greys out and shakes when tapped.
public struct KindButton: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var refusals = 0
    private let kind: CheckInKind
    private let onScene: Bool
    private let isAvailable: Bool
    private let action: () -> Void

    public init(_ kind: CheckInKind, onScene: Bool = false, isAvailable: Bool = true, action: @escaping () -> Void) {
        self.kind = kind
        self.onScene = onScene
        self.isAvailable = isAvailable
        self.action = action
    }

    public var body: some View {
        Button {
            if isAvailable {
                action()
            } else {
                refusals += 1
            }
        } label: {
            VStack(spacing: Space.xs - 2) {
                Image(systemName: kind.symbol)
                    .font(.system(size: Sizing.kindIcon * 0.8, weight: .semibold))
                    .foregroundStyle(Color(role: isAvailable ? .fgKind : .fgSubtle, in: theme))
                    .frame(width: Sizing.kindButton, height: Sizing.kindButton)
                    .background(Color(role: onScene ? .bgKindOnScene : .bgKind, in: theme), in: Circle())
                kind.shortName
                    .typeStyle(TypeRamp.label)
                    .foregroundStyle(Color(role: onScene ? .fgOnScene : .fgDefault, in: theme))
                    .fixedSize()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .shake(trigger: refusals, reduceMotion: reduceMotion)
        .accessibilityLabel(kind.fullName)
    }
}

/// A tag in the scene's wash with accent text, such as a check-in's kind in a list.
public struct Tag: View {
    @Environment(\.sceneTheme) private var theme
    private let title: Text
    private let systemImage: String?

    public init(_ title: Text, systemImage: String? = nil) {
        self.title = title
        self.systemImage = systemImage
    }

    public var body: some View {
        HStack(spacing: Space.xxs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: Sizing.smallIcon - 3, weight: .semibold))
                    .accessibilityHidden(true)
            }
            title
                .typeStyle(TypeRamp.footnoteEmphasis)
                .lineLimit(1)
        }
        .foregroundStyle(Color(role: .fgAccent, in: theme))
        .padding(.horizontal, Space.s)
        .frame(minHeight: Sizing.tag)
        .background(Color(role: .bgAccentSubtle, in: theme), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// A short no-shake for a tap that can't do anything, with a soft tick. Still with Reduce Motion.
    func shake(trigger: Int, reduceMotion: Bool) -> some View {
        keyframeAnimator(initialValue: 0.0, trigger: trigger) { content, shift in
            content.offset(x: reduceMotion ? 0 : shift)
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(-6, duration: 0.08)
                LinearKeyframe(5, duration: 0.08)
                LinearKeyframe(-3, duration: 0.08)
                LinearKeyframe(0, duration: 0.08)
            }
        }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.4), trigger: trigger)
    }
}
#endif
