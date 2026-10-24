#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// The one primary action on a screen (下一步, 打卡, 发布): a solid capsule in the accent tone's
/// colour (the scene's, the brand's under `.accentTone(.brand)`, or ink under `.accentTone(.ink)`), flat, that shrinks while held.
/// `.large` is 52 points tall and fills its width when the label asks for it; `.regular` is 44,
/// for an action inside content (去打卡). Disabled, it turns a quiet grey.
public struct PrimaryButtonStyle: ButtonStyle {
    public enum Size: Sendable {
        case large
        case regular
    }

    @Environment(\.sceneTheme) private var theme
    @Environment(\.accentTone) private var tone
    @Environment(\.isEnabled) private var isEnabled
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
            .background(Color(role: isEnabled ? tone.fill : .borderDefault, in: theme), in: Capsule())
            .contentShape(Capsule())
            .modifier(PressFeedback(isPressed: configuration.isPressed))
    }
}

/// A second action beside or under the primary one (换一组): a light grey capsule, 44 tall.
public struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.sceneTheme) private var theme

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .typeStyle(TypeRamp.calloutEmphasis)
            .lineLimit(1)
            .foregroundStyle(Color(role: .fgDefault, in: theme))
            .padding(.horizontal, Space.m + Space.xxs)
            .frame(minHeight: Sizing.control)
            .background(Color(role: .bgSubtle, in: theme), in: Capsule())
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

/// A word that acts: 以后再选 in muted ink, or 删除 in plain ink (deleting asks again; it is
/// never red). 44 tall, no fill.
public struct TextButtonStyle: ButtonStyle {
    public enum Tone: Sendable {
        case muted
        case plain
    }

    @Environment(\.sceneTheme) private var theme
    private let tone: Tone

    public init(_ tone: Tone = .muted) {
        self.tone = tone
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .typeStyle(TypeRamp.calloutEmphasis)
            .foregroundStyle(Color(role: tone == .muted ? .fgMuted : .fgDefault, in: theme))
            .padding(.horizontal, Space.s)
            .frame(minHeight: Sizing.control)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.wildcard(Motion.change), value: configuration.isPressed)
    }
}
#endif
