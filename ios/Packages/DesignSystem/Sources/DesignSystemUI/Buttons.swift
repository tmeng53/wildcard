#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// The one primary action on a screen (下一步, 打卡, 发布): a solid capsule in the accent tone's
/// colour (the scene's, the brand's under `.accentTone(.brand)`, or ink under `.accentTone(.ink)`), flat, that shrinks while held.
/// `.large` is 52 points tall and fills its width when the label asks for it; `.regular` is 44,
/// for an action inside content (去打卡). Disabled, it turns a quiet grey. Floating (in an
/// `actionBar` or under `.controlPlacement(.floating)`), it is interactive Liquid Glass tinted in
/// the tone's colour, as the system's prominent glass buttons are.
public struct PrimaryButtonStyle: ButtonStyle {
    public enum Size: Sendable {
        case large
        case regular
    }

    @Environment(\.sceneTheme) private var theme
    @Environment(\.accentTone) private var tone
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlPlacement) private var placement
    private let size: Size

    public init(_ size: Size = .large) {
        self.size = size
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .typeStyle(size == .large ? TypeRamp.action : TypeRamp.calloutEmphasis)
            .lineLimit(1)
            .foregroundStyle(Color(role: isEnabled ? tone.onFill : .fgSubtle, in: theme))
            .padding(.horizontal, size == .large ? Space.l : Space.m + Space.xxs)
            .frame(minHeight: size == .large ? Sizing.primaryControl : Sizing.control)
            .modifier(
                ControlSurface(placement: placement, fill: isEnabled ? tone.fill : .borderDefault, tinted: isEnabled)
            )
            .contentShape(Capsule())
            .modifier(PressFeedback(isPressed: configuration.isPressed))
    }
}

/// A button's capsule: solid in content, interactive Liquid Glass when it floats. A tinted one
/// (the primary action) carries its fill as the glass's tint; an untinted one is clear glass.
struct ControlSurface: ViewModifier {
    @Environment(\.sceneTheme) private var theme
    let placement: ControlPlacement
    let fill: ColorRole
    let tinted: Bool

    func body(content: Content) -> some View {
        switch placement {
        case .inContent:
            content.background(Color(role: fill, in: theme), in: Capsule())
        case .floating:
            content.glassEffect(
                tinted ? .regular.tint(Color(role: fill, in: theme)).interactive() : .regular.interactive(),
                in: Capsule())
        }
    }
}

/// A second action beside or under the primary one (换一组, 存图): the brand's graphite capsule
/// with white words, 44 tall, on a page or in a card alike (Tracy, 2026-11-08: one colour for
/// every secondary button). On graphite itself (`.onInk`: an `inkCard`, a graphite bar) it turns
/// white with ink words. An action that can't be taken back is a `TextButtonStyle(.danger)`,
/// never this. Floating, it is clear interactive Liquid Glass.
public struct SecondaryButtonStyle: ButtonStyle {
    public enum Surface: Sendable {
        /// The page, or a grey card on it.
        case page
        /// Graphite: an `inkCard` or a graphite bar.
        case onInk
    }

    @Environment(\.sceneTheme) private var theme
    @Environment(\.controlPlacement) private var controlPlacement
    private let surface: Surface

    public init(_ surface: Surface = .page) {
        self.surface = surface
    }

    private var words: ColorRole {
        if controlPlacement == .floating { return .fgDefault }
        return surface == .onInk ? .fgDefault : .fgOnBrand
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .typeStyle(TypeRamp.calloutEmphasis)
            .lineLimit(1)
            .foregroundStyle(Color(role: words, in: theme))
            .padding(.horizontal, Space.m + Space.xxs)
            .frame(minHeight: Sizing.control)
            .modifier(
                ControlSurface(
                    placement: controlPlacement, fill: surface == .onInk ? .bgCanvas : .bgBrand, tinted: false)
            )
            .contentShape(Capsule())
            .modifier(PressFeedback(isPressed: configuration.isPressed))
    }
}

/// Confirming with Apple (用 Apple 确认注销), in Apple's own black as its button guidelines ask.
/// `.filled` is Apple's black capsule, 52 tall and full width; `.outlined` is Apple's white button
/// with a black outline, 44 tall and as wide as its label, for when a gentler action is the
/// page's main one. Disabled, either turns a quiet grey.
public struct AppleButtonStyle: ButtonStyle {
    public enum Look: Sendable {
        case filled
        case outlined
    }

    @Environment(\.sceneTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    private let look: Look

    public init(_ look: Look = .filled) {
        self.look = look
    }

    public func makeBody(configuration: Configuration) -> some View {
        Group {
            switch look {
            case .filled:
                configuration.label
                    .typeStyle(TypeRamp.headline)
                    .lineLimit(1)
                    .foregroundStyle(isEnabled ? Color(Palette.white) : Color(role: .fgSubtle, in: theme))
                    .padding(.horizontal, Space.l)
                    .frame(maxWidth: .infinity, minHeight: Sizing.primaryControl)
                    .background(
                        isEnabled ? Color(Palette.appleBlack) : Color(role: .borderDefault, in: theme), in: Capsule())
            case .outlined:
                configuration.label
                    .typeStyle(TypeRamp.calloutEmphasis)
                    .lineLimit(1)
                    .foregroundStyle(isEnabled ? Color(Palette.appleBlack) : Color(role: .fgSubtle, in: theme))
                    .padding(.horizontal, Space.m + Space.xxs)
                    .frame(minHeight: Sizing.control)
                    .background(Color(Palette.white), in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(
                            isEnabled ? Color(Palette.appleBlack) : Color(role: .borderDefault, in: theme),
                            lineWidth: Sizing.hairline)
                    }
            }
        }
        .contentShape(Capsule())
        .modifier(PressFeedback(isPressed: configuration.isPressed))
    }
}

/// A word that acts: 以后再选 in muted ink, 删除 in plain ink (deleting asks again), or
/// 确认解雇 in `.danger` red, for the last step of an action that can't be taken back. 44 tall,
/// no fill.
public struct TextButtonStyle: ButtonStyle {
    public enum Tone: Sendable {
        case muted
        case plain
        case danger
    }

    @Environment(\.sceneTheme) private var theme
    private let tone: Tone

    public init(_ tone: Tone = .muted) {
        self.tone = tone
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .typeStyle(TypeRamp.calloutEmphasis)
            .foregroundStyle(Color(role: role, in: theme))
            .padding(.horizontal, Space.s)
            .frame(minHeight: Sizing.control)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.wildcard(Motion.change), value: configuration.isPressed)
    }

    private var role: ColorRole {
        switch tone {
        case .muted: .fgMuted
        case .plain: .fgDefault
        case .danger: .fgDanger
        }
    }
}
#endif
