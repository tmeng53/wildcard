#if canImport(SwiftUI)
import AvatarArt
import AvatarDomain
import Foundation
import Observation
import SwiftUI

/// Plays a character: idle on a loop, and clips such as a cheer on request. Views read
/// it every display frame; `play`, `wear` and `change` are the only things callers do.
@MainActor @Observable
public final class CharacterPlayer {
    public private(set) var drawing: FigureDrawing
    /// The outfit a change of clothes swaps in, drawn from the moment it goes on.
    private var nextDrawing: (from: Double, drawing: FigureDrawing)?
    private var performance: Performance
    /// Clip times count from here, so they stay small and precise.
    private let epoch: Date

    public init(figure: Figure, idle: Clip, now: Date = .now) throws(AvatarError) {
        drawing = FigureDrawing(figure)
        epoch = now
        performance = Performance(figure: figure, idle: try figure.bind(idle))
    }

    /// Switches to another outfit, idle or both from now, blending from the current pose, so
    /// a character being dressed doesn't snap. The figure must come from the same rig.
    public func wear(_ figure: Figure, idle: Clip, now: Date = .now) throws(AvatarError) {
        let bound = try figure.bind(idle)
        settle(at: now)
        // A kit still on its way in stays off: this outfit replaces it.
        nextDrawing = nil
        performance = Performance(
            continuing: performance, figure: figure, idle: bound, at: now.timeIntervalSince(epoch))
        drawing = FigureDrawing(figure)
    }

    /// Changes into another outfit with a hop, then plays `idle` in it: a sport's kit and move
    /// when the sport is picked (`PlaceholderCharacter.kitHop()` and `move(for:)`). Build
    /// `figure` before calling, so nothing is parsed mid-hop.
    public func change(
        into figure: Figure, idle: Clip, hop: (out: Clip, in: Clip), now: Date = .now
    ) throws(AvatarError) {
        let (move, out, back) = (try figure.bind(idle), try figure.bind(hop.out), try figure.bind(hop.in))
        settle(at: now)
        let time = now.timeIntervalSince(epoch)
        performance.change(into: figure, idle: move, leaving: out, arriving: back, at: time)
        nextDrawing = (time + hop.out.duration, FigureDrawing(figure))
    }

    /// The figure on screen.
    public var figure: Figure { performance.figure(at: .infinity) }

    /// Plays a clip from now, blending from the current pose unless `blending` is false (play
    /// `PlaceholderCharacter.entrance()` that way). One-shot clips return to idle; a change of
    /// clothes under way stops in the clothes on screen.
    public func play(_ clip: Clip, now: Date = .now, blending: Bool = true) throws(AvatarError) {
        settle(at: now)
        nextDrawing = nil
        performance.play(
            try performance.figure.bind(clip), at: now.timeIntervalSince(epoch), blending: blending)
    }

    /// What to draw at a moment: the outfit on screen then, and where its parts are.
    public func frame(at date: Date) -> (drawing: FigureDrawing, placements: [Placement]) {
        let time = date.timeIntervalSince(epoch)
        let drawing = nextDrawing.flatMap { time >= $0.from ? $0.drawing : nil } ?? drawing
        return (drawing, performance.figure(at: time).layout(performance.pose(at: time)))
    }

    /// Once a change of clothes has swapped the new outfit in, draws it from then on.
    private func settle(at date: Date) {
        if let next = nextDrawing, date.timeIntervalSince(epoch) >= next.from {
            drawing = next.drawing
            nextDrawing = nil
        }
    }

    /// The character standing still, for Reduce Motion: in the outfit it ends up in, holding
    /// its idle's first frame (`Performance.stillPose`).
    public var restFrame: (drawing: FigureDrawing, placements: [Placement]) {
        (nextDrawing?.drawing ?? drawing, figure.layout(performance.stillPose))
    }
}

/// A character that moves. It redraws on every display frame (60 or 120 times a second)
/// while on screen, and holds still at rest when Reduce Motion is on. Pass `crop`, in canvas
/// points, to fit another area than the canvas, such as the stage the 上场 entrance crosses.
public struct CharacterView: View {
    let player: CharacterPlayer
    let crop: CGRect?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(player: CharacterPlayer, crop: CGRect? = nil) {
        self.player = player
        self.crop = crop
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: reduceMotion)) { timeline in
            let frame = reduceMotion ? player.restFrame : player.frame(at: timeline.date)
            CharacterCanvas(drawing: frame.drawing, placements: frame.placements, crop: crop)
        }
        .aspectRatio(
            crop.map { $0.width / $0.height } ?? player.drawing.width / player.drawing.height, contentMode: .fit
        )
        // The figure is decoration; what it celebrates is said by the screen around it.
        .accessibilityHidden(true)
    }
}

#Preview("Placeholder character") {
    PlaceholderPreview()
}

/// Tap the character to cheer. For Xcode previews; the app wires the real thing.
private struct PlaceholderPreview: View {
    @State private var player = Self.makePlayer()

    var body: some View {
        if let player {
            CharacterView(player: player)
                .frame(height: 320)
                .onTapGesture { try? player.play(PlaceholderCharacter.clip("cheer", persona: .energetic)) }
        }
    }

    private static func makePlayer() -> CharacterPlayer? {
        try? CharacterPlayer(
            figure: PlaceholderCharacter.figure(wearing: PlaceholderCharacter.lifter),
            idle: PlaceholderCharacter.clip("idle", persona: .energetic))
    }
}
#endif
