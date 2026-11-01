#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// What a character says, in a small bubble with a tail pointing down at them: no border, no
/// shadow. `.line` is a 口头禅 or a cheer, one line of 13/600 up to 160 wide; `.info` is what a tap
/// on a person shows (their status, a 请假条's words, a caption), 13/400 up to 200 wide, with an
/// optional title line (name · kind); it wraps to show all of it, since those are words people
/// typed (a 请假条 is up to 80 characters) and a bubble can't be opened to read the rest. White on the scene, light grey on a page.
/// It pops in from its tail with `.speech(reduceMotion:)`; the caller keeps it `Motion.speechHold`.
/// Given an `action`, it is a button that opens what it says (a caption opens its post) and
/// shrinks while held like every other control. `.status` is a teammate's status with one thing
/// to do about it (拍一拍): the status in 13/600 over a muted detail, centred, and a compact
/// accent capsule under them; once done, the capsule turns grey and does nothing.
public struct SpeechBubble: View {
    public enum Kind {
        case line
        /// A line said in `.line`'s type that must show whole (a coach's catchphrase, which can be
        /// any length): it wraps at `.info`'s width instead of cutting off.
        case quote
        case info(title: Text?)
        case status(detail: Text?, button: StatusButton)
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
    private static let tail = CGSize(width: 12, height: 6)
    private static let verticalPadding: Double = 6
    private static let horizontalPadding: Double = 10

    public init(_ text: Text, kind: Kind = .line, on surface: CardSurface = .scene, action: (() -> Void)? = nil) {
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

    private var bubble: some View {
        content
            .padding(.vertical, isStatus ? Space.s - Space.xxs / 2 : Self.verticalPadding)
            .padding(.horizontal, isStatus ? Space.s : Self.horizontalPadding)
            .background(fill, in: RoundedRectangle(cornerRadius: Radius.pick, style: .continuous))
            .padding(.bottom, Self.tail.height)
            .background(alignment: .bottom) {
                Tail()
                    .fill(fill)
                    .frame(width: Self.tail.width, height: Self.tail.height)
            }
    }

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
                            .foregroundStyle(Color(role: .fgMuted, in: theme))
                            .lineLimit(1)
                    }
                    text
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(Color(role: .fgDefault, in: theme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .status(let detail, let button):
            HuggingWidth(min: Self.statusMinWidth - 2 * Space.s, max: Self.statusWidth - 2 * Space.s) {
                VStack(spacing: Space.xxs / 2) {
                    text
                        .typeStyle(TypeRamp.footnoteEmphasis)
                        .foregroundStyle(Color(role: .fgDefault, in: theme))
                        .lineLimit(1)
                    if let detail {
                        detail
                            .typeStyle(TypeRamp.footnote)
                            .foregroundStyle(Color(role: .fgMuted, in: theme))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    StatusCapsule(button: button)
                        .padding(.top, Space.xs - Space.xxs / 2)
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

    private var fill: Color {
        Color(role: surface == .scene ? .bgCanvas : .bgSubtle, in: theme)
    }
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

/// The accent capsule in a `.status` bubble, `compactControl` tall; grey once done.
private struct StatusCapsule: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accentTone) private var tone
    let button: SpeechBubble.StatusButton

    var body: some View {
        Button {
            if !button.isDone { button.action() }
        } label: {
            button.label
                .typeStyle(TypeRamp.calloutEmphasis)
                .lineLimit(1)
                .foregroundStyle(Color(role: button.isDone ? .fgSubtle : tone.onFill, in: theme))
                .padding(.horizontal, Space.m)
                .frame(height: Sizing.compactControl)
                .background(Color(role: button.isDone ? .bgSubtle : tone.fill, in: theme), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .allowsHitTesting(!button.isDone)
        .accessibilityIdentifier(button.identifier ?? "")
        .accessibilityAddTraits(button.isDone ? [.isStaticText] : [])
        .accessibilityRemoveTraits(button.isDone ? [.isButton] : [])
    }
}

/// A triangle pointing down from the middle of the bubble's bottom edge.
private struct Tail: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.closeSubpath()
        }
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
