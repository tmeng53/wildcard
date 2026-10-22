#if os(iOS)
import CheckInDomain
import Contracts
import DesignSystem
import DesignSystemUI
import SwiftUI

/// When the squad cheers me, each teammate who joins in shouts their line over their head at
/// their persona's beat, for about two seconds.
struct CheerBubbles: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let cast: SquadCast
    let unit: Double

    @State private var shown: Set<MemberID> = []

    /// How long a line stays up.
    private static let hold = 1.8
    /// How far above the feet a bubble's tail ends, in the rig's points: just over the head.
    private static let headHeight = 250.0
    /// The widest a line's bubble gets (`SpeechBubble`'s line width) and how far it keeps from
    /// the screen's edge, in the stage's points.
    private static let widest = 160.0
    private static let margin = 12.0

    private static func centre(over head: Double) -> Double {
        min(max(head, widest / 2 + margin), StageLayout.width - widest / 2 - margin)
    }

    var body: some View {
        ZStack {
            ForEach(cast.mates.filter { shown.contains($0.id) }) { mate in
                if let position = cast.stage.position(of: mate.id, at: 0) {
                    // Over the head, but never past the screen's edge for someone at the side.
                    Color.clear
                        .frame(width: Self.widest * unit, height: 0)
                        .overlay(alignment: .bottom) {
                            SpeechBubble(Text(verbatim: mate.line))
                                .fixedSize()
                        }
                        .position(
                            x: Self.centre(over: position.point.x) * unit,
                            y: (position.point.y - Self.headHeight * position.scale) * unit
                        )
                        .transition(.speech(reduceMotion: reduceMotion))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: cast.cheer) { await play(cast.cheer.order) }
    }

    /// `order` is already by beat.
    private func play(_ order: [MemberID]) async {
        guard !order.isEmpty else { return }
        var elapsed = 0.0
        for id in order {
            guard let mate = cast.mates.first(where: { $0.id == id }) else { continue }
            let beat = SquadCast.cheerDelay(mate.persona)
            try? await Task.sleep(for: .seconds(beat - elapsed))
            elapsed = beat
            withAnimation(.wildcard(Motion.sheet, reduceMotion: reduceMotion)) { _ = shown.insert(id) }
        }
        try? await Task.sleep(for: .seconds(Self.hold))
        withAnimation(.wildcard(Motion.sheet, reduceMotion: reduceMotion)) { shown = [] }
    }
}
#endif
