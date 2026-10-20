#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// What the character says (口头禅, a cheer, a check-in's caption): a white bubble with a small
/// tail under it. A long line wraps, centered, within whatever width the caller gives it. It
/// pops in with `.speech(reduceMotion:)`.
public struct SpeechBubble: View {
    @Environment(\.sceneTheme) private var theme
    private let text: Text

    /// The tail's size, as a square rotated 45 degrees.
    private static let tail: Double = 10
    private static let tailRounding: Double = 2

    public init(_ text: Text) {
        self.text = text
    }

    public var body: some View {
        text
            .typeStyle(TypeRamp.calloutEmphasis)
            .foregroundStyle(Color(role: .fgDefault, in: theme))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Space.s)
            .padding(.vertical, Space.xs - 1)
            .background {
                let fill = Color(role: .bgCanvas, in: theme)
                RoundedRectangle(cornerRadius: Radius.pick, style: .continuous)
                    .fill(fill)
                    .overlay(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: Self.tailRounding, style: .continuous)
                            .fill(fill)
                            .frame(width: Self.tail, height: Self.tail)
                            .rotationEffect(.degrees(45))
                            .offset(y: Self.tail / 2)
                    }
            }
            .padding(.bottom, Self.tail / 2)
    }
}

extension AnyTransition {
    /// A speech bubble popping out of the character, or fading with Reduce Motion on.
    public static func speech(reduceMotion: Bool) -> AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .scale(scale: 0.6, anchor: .bottom).combined(with: .opacity)
    }
}
#endif
