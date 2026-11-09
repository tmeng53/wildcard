#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// The "done" moment (approved 2026-11-08): the logo's two tickets bounce once, the W on the front
/// ticket fades and a check draws in its place, then `words` fade up under it, graphite on the
/// page's own light canvas. It plays once when
/// it appears (`TicketCheckTiming`); with Reduce Motion it shows its last frame. Use it for any
/// success that needs a check, rather than a new one.
public struct TicketCheck<Words: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sceneTheme) private var theme
    @State private var start = Date()
    private let size: CGFloat
    private let label: Text
    private let words: Words

    /// - Parameters:
    ///   - size: the mark's width and height, in points.
    ///   - label: what VoiceOver says for the mark, such as 已发送.
    public init(size: CGFloat = 140, label: Text, @ViewBuilder words: () -> Words) {
        self.size = size
        self.label = label
        self.words = words()
    }

    public var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let frame =
                reduceMotion
                ? TicketCheckTiming.Frame.done
                : TicketCheckTiming.frame(at: timeline.date.timeIntervalSince(start))
            VStack(spacing: Space.l) {
                Canvas { context, canvas in
                    TicketMark.draw(
                        in: &context, size: canvas, rock: frame.rock,
                        ground: Color(role: .bgCanvas, in: theme), ink: Color(role: .bgBrand, in: theme),
                        letter: frame.letter, check: frame.check)
                }
                .frame(width: size, height: size)
                .accessibilityElement()
                .accessibilityLabel(label)
                words
                    .opacity(frame.words)
                    .offset(y: (1 - frame.words) * 6)
            }
        }
        .onAppear { start = Date() }
    }
}
#endif
