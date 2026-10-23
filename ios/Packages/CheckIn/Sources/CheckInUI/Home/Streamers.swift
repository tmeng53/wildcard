#if os(iOS)
import DesignSystem
import DesignSystemUI
import SwiftUI

/// About twenty streamers that drift down from the top of the screen when I train: the scene's
/// colours and ink, swaying as they fall, gone after about two seconds. Plays each time
/// `trigger` changes; not at all with Reduce Motion.
struct Streamers<Trigger: Equatable>: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let trigger: Trigger

    @State private var startedAt: Date?

    private static var count: Int { 22 }
    private static var duration: Double { 2.2 }
    /// A streamer is a 6 by 18 strip with softened ends.
    private static var rounding: CGSize { CGSize(width: 2, height: 2) }

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: startedAt == nil)) { timeline in
            Canvas { context, size in
                guard let startedAt else { return }
                let age = timeline.date.timeIntervalSince(startedAt)
                guard age < Self.duration else { return }
                let colors = [
                    Color(role: .ring, in: theme), Color(role: .bgAccent, in: theme),
                    Color(role: .fgDefault, in: theme),
                ]
                for index in 0..<Self.count {
                    draw(index, age: age, colors: colors, in: &context, size: size)
                }
            }
        }
        .onChange(of: trigger) {
            guard !reduceMotion else { return }
            startedAt = .now
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(Self.duration))
                startedAt = nil
            }
        }
        .accessibilityHidden(true)
    }

    /// One streamer: its own column, delay, speed and sway, the same every time.
    private func draw(_ index: Int, age: Double, colors: [Color], in context: inout GraphicsContext, size: CGSize) {
        let seed = Double(index)
        let column = (seed * 0.618).truncatingRemainder(dividingBy: 1)
        let delay = (seed * 0.137).truncatingRemainder(dividingBy: 0.35)
        let time = max(0, age - delay)
        let speed = size.height * (0.32 + (seed * 0.29).truncatingRemainder(dividingBy: 0.18))
        let fall = time * speed - 40
        let sway = sin(time * 4 + seed) * 18
        let fade = min(1, max(0, (Self.duration - age) / 0.5))
        var piece = context
        piece.opacity = fade
        piece.translateBy(x: column * size.width + sway, y: fall)
        piece.rotate(by: .radians(sin(time * 6 + seed * 2) * 0.9))
        let rect = CGRect(x: -3, y: -9, width: 6, height: 18)
        piece.fill(Path(roundedRect: rect, cornerSize: Self.rounding), with: .color(colors[index % colors.count]))
    }
}
#endif
