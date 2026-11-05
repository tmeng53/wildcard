#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// What a character says, in a small bubble with a tail pointing down at them. Over the scene it
/// is light Liquid Glass (the system's `glassEffect`, tinted white so ink words read on any scene,
/// day or night), the bubble and its tail one piece of glass; on a page, plain light grey, since
/// glass on a flat fill shows nothing. `.line` is a 口头禅 or a cheer, one line of 13/600 up to
/// 160 wide; `.info` is what a tap on a person shows (their status, a 请假条's words, a caption), 13/400 up to 200 wide, with an
/// optional title line (name · kind); it wraps to show all of it, since those are words people
/// typed (a 请假条 is up to 80 characters) and a bubble can't be opened to read the rest.
/// It pops in from its tail with `.speech(reduceMotion:)`; the caller keeps it `Motion.speechHold`.
/// Given an `action`, it is a button that opens what it says (a caption opens its post) and
/// shrinks while held like every other control. `.status` is a teammate's status with one thing
/// to do about it (拍一拍): the status in 13/600 over a muted detail, centred, and a small
/// accent capsule under them; once done, only a muted 「✓ 拍过了」 line. My own status
/// has nothing to do: no capsule.
public struct SpeechBubble: View {
    public enum Kind {
        case line
        /// A line said in `.line`'s type that must show whole (a coach's catchphrase, which can be
        /// any length): it wraps at `.info`'s width instead of cutting off.
        case quote
        case info(title: Text?)
        case status(detail: Text?, button: StatusButton?)
    }

    /// The capsule under a `.status` bubble's words.
    public struct StatusButton {
        let label: Text
        let isDone: Bool
        let identifier: String?
        let action: () -> Void

        /// - Parameters:
        ///   - isDone: already done: grey, and a tap does nothing.
        ///   - identifier: the button's accessibility identifier, for UI tests.
        public init(_ label: Text, isDone: Bool, identifier: String? = nil, action: @escaping () -> Void) {
            self.label = label
            self.isDone = isDone
            self.identifier = identifier
            self.action = action
        }
    }

    @Environment(\.sceneTheme) private var theme
    private let text: Text
    private let kind: Kind
    private let surface: CardSurface
    private let action: (() -> Void)?

    private static let lineWidth: Double = 160
    private static let infoWidth: Double = 200
    private static let tailSize = CGSize(width: 12, height: 6)
    private static let verticalPadding: Double = 6
    private static let horizontalPadding: Double = 10

    public init(
        _ text: Text, kind: Kind = .line, on surface: CardSurface = .scene,
        action: (() -> Void)? = nil
    ) {
        self.text = text
        self.kind = kind
        self.surface = surface
        self.action = action
    }

    public var body: some View {
        if let action {
            Button(action: action) { bubble }
                .buttonStyle(PressableButtonStyle())
        } else {
            bubble
        }
    }

    @ViewBuilder private var bubble: some View {
        let padded =
            content
            .padding(.top, isStatus ? Space.s : Self.verticalPadding)
            .padding(.bottom, isStatus ? Space.s + Space.xxs / 2 : Self.verticalPadding)
            .padding(.horizontal, isStatus ? Space.m : Self.horizontalPadding)
            .padding(.bottom, Self.tailSize.height)
        switch surface {
        case .scene:
            padded.glassEffect(.regular.tint(Color(role: .bgCanvas, in: theme).opacity(Self.glassTint)), in: shape)
        case .page:
            padded.background(Color(role: .bgSubtle, in: theme), in: shape)
        }
    }

    private var shape: BubbleShape {
        BubbleShape(tail: Self.tailSize, cornerRadius: Radius.pick)
    }

    /// How much white the glass carries: enough that a coloured scene (the red track) doesn't dye
    /// it and ink words read at night, little enough that the scene still shows through.
    private static let glassTint = 0.72

    /// A title or detail's colour: on glass, ink at `glassMuted`, which takes on the scene's hue
    /// through the glass where a fixed grey would look dirty on a coloured scene; on a page, muted.
    private var muted: Color {
        surface == .scene
            ? Color(role: .fgDefault, in: theme).opacity(Self.glassMuted) : Color(role: .fgMuted, in: theme)
    }

    private static let glassMuted = 0.55

    @ViewBuilder private var content: some View {
        switch kind {
        case .line:
            HuggingWidth(max: Self.lineWidth - 2 * Self.horizontalPadding) {
                text
                    .typeStyle(TypeRamp.footnoteEmphasis)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .lineLimit(1)
            }
        case .quote:
            HuggingWidth(max: Self.infoWidth - 2 * Self.horizontalPadding) {
                text
                    .typeStyle(TypeRamp.footnoteEmphasis)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .info(let title):
            HuggingWidth(max: Self.infoWidth - 2 * Self.horizontalPadding) {
                VStack(alignment: .leading, spacing: Space.xxs / 2) {
                    if let title {
                        title
                            .typeStyle(TypeRamp.label)
                            .foregroundStyle(muted)
                            .lineLimit(1)
                    }
                    text
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(Color(role: .fgDefault, in: theme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .status(let detail, let button):
            HuggingWidth(min: Self.statusMinWidth - 2 * Space.m, max: Self.statusWidth - 2 * Space.m) {
                // Two groups with room between them: what they're up to, then the one thing to do.
                VStack(spacing: 0) {
                    VStack(spacing: Space.xxs / 2) {
                        text
                            .typeStyle(TypeRamp.footnoteEmphasis)
                            .foregroundStyle(Color(role: .fgDefault, in: theme))
                            .lineLimit(1)
                        if let detail {
                            detail
                                .typeStyle(TypeRamp.footnote)
                                .foregroundStyle(muted)
                                .lineSpacing(Space.xxs / 2)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if let button {
                        StatusCapsule(button: button)
                            .padding(.top, Space.xs)
                    }
                }
            }
        }
    }

    private var isStatus: Bool {
        if case .status = kind { true } else { false }
    }

    /// A `.status` bubble's narrowest and widest, from the approved home 拍一拍.
    private static let statusMinWidth: Double = 120
    private static let statusWidth: Double = 220
}

/// Offers its content at most `max` wide and takes only the width the content uses (at least
/// `min`), so a bubble hugs its words however wide its caller offers it. A
/// `.frame(maxWidth:)` would instead stretch to whatever it is offered, up to its max.
private struct HuggingWidth: Layout {
    var min: Double = 0
    let max: Double

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let size = content.sizeThatFits(offer(proposal))
        return CGSize(width: Swift.max(min, size.width), height: size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: CGPoint(x: bounds.midX, y: bounds.minY), anchor: .top, proposal: offer(proposal))
    }

    private func offer(_ proposal: ProposedViewSize) -> ProposedViewSize {
        ProposedViewSize(width: Swift.min(proposal.width ?? max, max), height: nil)
    }
}

/// What to do in a `.status` bubble: a small accent capsule, and once done, only a muted
/// 「✓ 拍过了」 line, which does nothing, so a done bubble sits lower and lighter.
private struct StatusCapsule: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accentTone) private var tone
    let button: SpeechBubble.StatusButton

    var body: some View {
        if button.isDone {
            HStack(spacing: Space.xxs) {
                Image(systemName: "checkmark")
                    .font(.system(size: Self.check, weight: .semibold))
                    .accessibilityHidden(true)
                button.label
                    .typeStyle(TypeRamp.label)
                    .lineLimit(1)
            }
            .foregroundStyle(Color(role: .fgSubtle, in: theme))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(button.identifier ?? "")
            .accessibilityAddTraits(.isStaticText)
        } else {
            Button(action: button.action) {
                button.label
                    .typeStyle(TypeRamp.footnoteEmphasis)
                    .lineLimit(1)
                    .foregroundStyle(Color(role: tone.onFill, in: theme))
                    .padding(.horizontal, Space.s + Space.xxs / 2)
                    .padding(.vertical, Space.xxs + Space.xxs / 2)
                    .background(Color(role: tone.fill, in: theme), in: Capsule())
                    // The capsule is small; the tap lands on a taller target around it.
                    .contentShape(Rectangle().inset(by: -(Space.xxs + Space.xxs / 2)))
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityIdentifier(button.identifier ?? "")
        }
    }

    private static let check: Double = 10
}

/// A bubble and its tail as one outline, so glass bends light across both as one piece: a
/// rounded rectangle above `tail.height`, and a triangle under it pointing down from its middle.
private struct BubbleShape: Shape {
    let tail: CGSize
    let cornerRadius: Double

    func path(in rect: CGRect) -> Path {
        let body = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - tail.height)
        let mid = rect.midX
        // The triangle reaches a point into the body so no seam shows where they join.
        let point = Path { path in
            path.move(to: CGPoint(x: mid - tail.width / 2, y: body.maxY - 1))
            path.addLine(to: CGPoint(x: mid + tail.width / 2, y: body.maxY - 1))
            path.addLine(to: CGPoint(x: mid, y: rect.maxY))
            path.closeSubpath()
        }
        return Path(roundedRect: body, cornerRadius: cornerRadius, style: .continuous).union(point)
    }
}

extension AnyTransition {
    /// A speech bubble popping out of its tail on `celebrate` (0.6 to full size) and fading out
    /// over `Motion.speechFade`; with Reduce Motion on, a fade both ways.
    public static func speech(reduceMotion: Bool) -> AnyTransition {
        let fadeOut = AnyTransition.opacity.animation(.easeOut(duration: Motion.speechFade))
        if reduceMotion {
            return .asymmetric(
                insertion: .opacity.animation(.easeOut(duration: Motion.reducedDuration)), removal: fadeOut)
        }
        return .asymmetric(
            insertion: AnyTransition.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity)
                .animation(.wildcard(Motion.celebrate)),
            removal: fadeOut)
    }
}
#endif
