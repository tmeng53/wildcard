#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// Names and symbols for scenes and check-in kinds, shared by the style guide and the screens.
extension SceneTheme {
    /// The scene's name (「第 42 周 · 跑道」); a scene added since this build, the catalog's.
    public var name: Text {
        if Base(rawValue: rawValue) == nil, let listed = Self.listing(self) {
            return Text(verbatim: listed.name(in: AppLanguage.current))
        }
        return switch base {
        case .pool: Text(copy: "游泳池", bundle: .module)
        case .track: Text(copy: "跑道", bundle: .module)
        case .gym: Text(copy: "健身房", bundle: .module)
        case .tennis: Text(copy: "网球场", bundle: .module)
        case .climbing: Text(copy: "攀岩馆", bundle: .module)
        case .ski: Text(copy: "雪场", bundle: .module)
        }
    }
}

extension SceneTheme.Listing {
    /// The name in `language`.
    func name(in language: AppLanguage) -> String {
        switch language {
        case .simplifiedChinese: simplifiedChinese
        case .traditionalChinese: traditionalChinese
        case .english: english
        }
    }
}

extension CheckInKind {
    /// The short label on a kind button or a check-in capsule.
    public var shortName: Text {
        switch self {
        case .trained: Text(copy: "训练", bundle: .module)
        case .healthyMeal: Text(copy: "健康餐", bundle: .module)
        case .cheatMeal: Text(copy: "放纵餐", bundle: .module)
        case .disclaimer: Text(copy: "请假", bundle: .module)
        }
    }

    /// The full name, for titles.
    public var fullName: Text {
        switch self {
        case .trained: Text(copy: "训练", bundle: .module)
        case .healthyMeal: Text(copy: "健康餐", bundle: .module)
        case .cheatMeal: Text(copy: "坦白放纵餐", bundle: .module)
        case .disclaimer: Text(copy: "今日请假条", bundle: .module)
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
/// scene's floor. Unavailable, it greys out and shakes when tapped.
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

/// A short label on a capsule: a post's kind in the scene's wash (`.accent`), a 请假条 or rest
/// day in grey (`.rest`, usually with the moon), or a status in ink (`.ink`: 求职中, 你们的教练).
/// `.small` is 20 tall in footnote-sized words, for a tag inside a row or beside a name; the
/// regular one is 28. Every small label the app draws on a capsule is a `Tag`.
public struct Tag: View {
    public enum Style: Sendable {
        case accent
        case rest
        case ink
    }

    public enum Size: Sendable {
        case regular
        case small
    }

    @Environment(\.sceneTheme) private var theme
    private let title: Text
    private let systemImage: String?
    private let style: Style
    private let size: Size

    public init(_ title: Text, systemImage: String? = nil, style: Style = .accent, size: Size = .regular) {
        self.title = title
        self.systemImage = systemImage
        self.style = style
        self.size = size
    }

    public var body: some View {
        HStack(spacing: Space.xxs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(
                        .system(size: size == .regular ? Sizing.smallIcon - 3 : Sizing.smallIcon - 6, weight: .semibold)
                    )
                    .accessibilityHidden(true)
            }
            title
                .typeStyle(size == .regular ? TypeRamp.footnoteEmphasis : TypeRamp.label)
                .lineLimit(1)
        }
        .foregroundStyle(Color(role: foreground, in: theme))
        .padding(.horizontal, size == .regular ? Space.s : Space.xs)
        .frame(minHeight: size == .regular ? Sizing.tag : Sizing.smallTag)
        .background(Color(role: background, in: theme), in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private var foreground: ColorRole {
        switch style {
        case .accent: .fgAccent
        case .rest: .fgMuted
        case .ink: .fgOnInk
        }
    }

    private var background: ColorRole {
        switch style {
        case .accent: .bgAccentSubtle
        case .rest: .borderDefault
        case .ink: .bgInk
        }
    }
}

/// A line between rows or sections, edge to edge: the page's border grey, or a light line on
/// ink (`.ink`, the player card).
public struct Hairline: View {
    public enum Surface: Sendable {
        case page
        case ink
    }

    @Environment(\.sceneTheme) private var theme
    private let surface: Surface

    public init(on surface: Surface = .page) {
        self.surface = surface
    }

    public var body: some View {
        Rectangle()
            .fill(Color(role: surface == .page ? .borderDefault : .borderOnInk, in: theme))
            .frame(height: Sizing.hairline)
            .accessibilityHidden(true)
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
        .haptic(.refuse, trigger: trigger)
    }
}
#endif
