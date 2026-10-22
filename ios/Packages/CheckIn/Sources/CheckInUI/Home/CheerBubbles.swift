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

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(cast.mates.filter { shown.contains($0.id) }) { mate in
                if let position = cast.stage.position(of: mate.id, at: 0) {
                    SpeechBubble(Text(verbatim: mate.line))
                        .fixedSize()
                        .alignmentGuide(.top) { $0[.bottom] }
                        .alignmentGuide(.leading) { $0.width / 2 }
                        .offset(
                            x: position.point.x * unit,
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
