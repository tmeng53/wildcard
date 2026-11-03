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
/// accent capsule under them; once done, the capsule turns grey and does nothing. My own status
/// has nothing to do: no capsule. `.coach` is what the AI coach says: `CoachTag` and its name over
/// its words in `.info`'s type, wrapped whole.
///
/// The tail points down from the middle, or, with `tail: .leading`, from near the bubble's
/// leading corner, for a speaker by the screen's edge.
public struct SpeechBubble: View {
    /// Where the tail leaves the bubble's bottom edge.
    public enum TailSpot {
        case center
        case leading
    }

    public enum Kind {
        case line
        /// A line said in `.line`'s type that must show whole (a coach's catchphrase, which can be
        /// any length): it wraps at `.info`'s width instead of cutting off.
        case quote
        case info(title: Text?)
        case status(detail: Text?, button: StatusButton?, eyebrow: StatusEyebrow? = nil)
        case coach(name: Text)
    }

    /// A small muted line over a `.status` bubble's words: who it is (name · the title they wear,
    /// its badge before them), which opens their player card.
    public struct StatusEyebrow {
        let label: Text
        /// The worn title's badge.
        let badge: TitleBadgeLook?
        let identifier: String?
        let action: () -> Void

        public init(_ label: Text, badge: TitleBadgeLook?, identifier: String? = nil, action: @escaping () -> Void) {
            self.label = label
            self.badge = badge
            self.identifier = identifier
            self.action = action
        }
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
    private let tail: TailSpot

    private static let lineWidth: Double = 160
    private static let infoWidth: Double = 200
    private static let tailSize = CGSize(width: 12, height: 6)
    private static let verticalPadding: Double = 6
    private static let horizontalPadding: Double = 10

    /// The tail's middle from the bubble's leading edge, with `tail: .leading`.
    public static let leadingTail: Double = 32

    public init(
        _ text: Text, kind: Kind = .line, on surface: CardSurface = .scene, tail: TailSpot = .center,
        action: (() -> Void)? = nil
    ) {
        self.text = text
        self.kind = kind
        self.surface = surface
        self.tail = tail
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
            .padding(.bottom, Self.tailSize.height)
            .background(alignment: tail == .leading ? .bottomLeading : .bottom) {
                Tail()
                    .fill(fill)
                    .frame(width: Self.tailSize.width, height: Self.tailSize.height)
                    .padding(.leading, tail == .leading ? Self.leadingTail - Self.tailSize.width / 2 : 0)
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
        case .coach(let name):
            HuggingWidth(max: Self.infoWidth - 2 * Self.horizontalPadding) {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    HStack(spacing: Space.xxs + Space.xxs / 2) {
                        CoachTag()
                        name
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
        case .status(let detail, let button, let eyebrow):
            HuggingWidth(min: Self.statusMinWidth - 2 * Space.s, max: Self.statusWidth - 2 * Space.s) {
                VStack(spacing: Space.xxs / 2) {
                    if let eyebrow {
                        EyebrowLine(eyebrow: eyebrow)
                    }
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
                    if let button {
                        StatusCapsule(button: button)
                            .padding(.top, Space.xs - Space.xxs / 2)
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

/// The muted name line over a `.status` bubble, a button to their card: the worn title's badge
/// small before the words.
private struct EyebrowLine: View {
    @Environment(\.sceneTheme) private var theme
    let eyebrow: SpeechBubble.StatusEyebrow

    var body: some View {
        Button(action: eyebrow.action) {
            HStack(spacing: Space.xxs) {
                if let badge = eyebrow.badge {
                    TitleBadgeView(badge, size: Self.badge)
                }
                eyebrow.label
                    .typeStyle(TypeRamp.caption)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Image(systemName: "chevron.right")
                    .font(.system(size: Self.chevron, weight: .semibold))
                    .foregroundStyle(Color(role: .fgSubtle, in: theme))
                    .accessibilityHidden(true)
            }
            // A taller target than the line, as a tap on a name should land.
            .frame(minHeight: Sizing.compactControl / 2 + Space.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityIdentifier(eyebrow.identifier ?? "")
    }

    private static let badge: Double = 16
    private static let chevron: Double = 9
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
