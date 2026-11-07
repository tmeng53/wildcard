#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// The launch cover's logo and WILDCARD on graphite, played by `LaunchWave` (design A 字母浪):
/// it starts as the system's launch screen, the logo alone at 112 points in the middle of the
/// screen, then the logo lifts and the word pops up under it, and the tickets rock and the
/// letters wave for as long as the cover is up. Laid out over the whole screen, as the system's
/// launch screen is, and at a fixed size, so the first frame matches it. With Reduce Motion it
/// stands still, the word already in place.
public struct LaunchWordmark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// When the cover appeared: the motion counts from here.
    private let start: Date

    public init(start: Date) {
        self.start = start
    }

    public var body: some View {
        let ground = Color(role: .bgBrand, in: .gym)
        let ink = Color(role: .fgOnBrand, in: .gym)
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let time = reduceMotion ? LaunchWave.entrance : max(0, timeline.date.timeIntervalSince(start))
            ZStack {
                Canvas { context, canvas in
                    TicketMark.draw(
                        in: &context, size: canvas, rock: LaunchWave.rock(at: time), ground: ground, ink: ink)
                }
                .frame(width: Self.logo, height: Self.logo)
                .offset(y: -LaunchWave.logoLift(at: time))
                HStack(spacing: 0) {
                    ForEach(Array(LaunchWave.word.enumerated()), id: \.offset) { index, letter in
                        let place = LaunchWave.letter(index, at: time)
                        Text(verbatim: String(letter))
                            .typeStyle(TypeRamp.launchWord)
                            .foregroundStyle(ink)
                            .offset(y: place.offset)
                            .opacity(place.opacity)
                    }
                }
                .fixedSize()
                // The word's top sits this far under the screen's centre once the logo has lifted.
                .offset(y: Self.wordDrop)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(ground)
        .dynamicTypeSize(.large)
        .accessibilityElement()
        .accessibilityLabel(Text(copy: "加载中", bundle: .module))
    }

    /// The logo's size, as on the system's launch screen (`LaunchMark`).
    private static let logo: CGFloat = 112
    /// How far below the screen's centre the word's centre is.
    private static let wordDrop: CGFloat = 78
}
#endif
