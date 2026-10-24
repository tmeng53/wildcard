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

    var body: some View {
        ZStack {
            ForEach(cast.mates.filter { shown.contains($0.id) }) { mate in
                if let position = cast.stage.position(of: mate.id, at: 0) {
                    HeadBubble(line: mate.line, position: position, unit: unit)
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

/// When the lights wake the squad at night (开灯), the first sleeper mumbles their persona's
/// line over their head at `LightsFlip.lineAt`, for `Motion.speechHold`. Not under Reduce Motion.
struct WokenLine: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let cast: SquadCast
    let pull: TodayModel.LightsPull?
    let unit: Double

    @State private var speaker: MemberID?

    var body: some View {
        ZStack {
            if let speaker, let mate = cast.mates.first(where: { $0.id == speaker }),
                let position = cast.stage.position(of: speaker, at: 0)
            {
                HeadBubble(line: SquadCast.wokenLine(mate.persona), position: position, unit: unit)
                    .transition(.speech(reduceMotion: reduceMotion))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: pull) { await play() }
    }

    private func play() async {
        speaker = nil
        guard let pull, pull.isOn, !reduceMotion, let first = cast.sleepers.first else { return }
        try? await Task.sleep(for: .seconds(LightsFlip.lineAt - Date.now.timeIntervalSince(pull.start)))
        guard !Task.isCancelled else { return }
        withAnimation(.wildcard(Motion.sheet, reduceMotion: reduceMotion)) { speaker = first.id }
        try? await Task.sleep(for: .seconds(Motion.speechHold))
        guard !Task.isCancelled else { return }
        withAnimation(.wildcard(Motion.sheet, reduceMotion: reduceMotion)) { speaker = nil }
    }
}

/// A line in a speech bubble over a teammate's head, slid in just enough to stay on screen for
/// someone at the side.
struct HeadBubble: View {
    let line: String
    let position: StagePosition
    let unit: Double

    /// How far above the feet a bubble's tail ends, in the rig's points: just over the head.
    private static let headHeight = 250.0
    /// How far a bubble keeps from the screen's edge.
    private static let margin = Space.s

    /// Where a bubble `width` wide centres over a `head`, kept on the stage's width.
    private static func centre(of width: Double, over head: Double, unit: Double) -> Double {
        let stage = StageLayout.width * unit
        return min(max(head, width / 2 + margin), stage - width / 2 - margin)
    }

    var body: some View {
        let head = position.point.x * unit
        Color.clear
            .frame(width: 0, height: 0)
            .overlay(alignment: .bottom) {
                SpeechBubble(Text(verbatim: line))
                    .fixedSize()
                    .alignmentGuide(HorizontalAlignment.center) { bubble in
                        bubble.width / 2 + head - Self.centre(of: bubble.width, over: head, unit: unit)
                    }
            }
            .position(x: head, y: (position.point.y - Self.headHeight * position.scale) * unit)
    }
}
#endif
