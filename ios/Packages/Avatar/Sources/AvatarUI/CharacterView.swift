#if canImport(SwiftUI)
import AvatarArt
import AvatarDomain
import Foundation
import Observation
import SwiftUI

/// Plays a character: idle on a loop, and clips such as a cheer on request. Views read
/// it every display frame; `play` is the only thing callers do.
@MainActor @Observable
public final class CharacterPlayer {
    public let drawing: FigureDrawing
    private var performance: Performance
    /// Clip times count from here, so they stay small and precise.
    private let epoch: Date

    public init(figure: Figure, idle: Clip, now: Date = .now) throws(AvatarError) {
        drawing = FigureDrawing(figure)
        epoch = now
        performance = Performance(figure: figure, idle: try figure.bind(idle))
    }

    /// Plays a clip from now, blending from the current pose. One-shot clips return to idle.
    public func play(_ clip: Clip, now: Date = .now) throws(AvatarError) {
        performance.play(try performance.figure.bind(clip), at: now.timeIntervalSince(epoch))
    }

    public func placements(at date: Date) -> [Placement] {
        performance.figure.layout(performance.pose(at: date.timeIntervalSince(epoch)))
    }

    public var restPlacements: [Placement] {
        performance.figure.layout(performance.figure.restPose)
    }
}

/// A character that moves. It redraws on every display frame (60 or 120 times a second)
/// while on screen, and holds still at rest when Reduce Motion is on.
public struct CharacterView: View {
    let player: CharacterPlayer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(player: CharacterPlayer) {
        self.player = player
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: reduceMotion)) { timeline in
            CharacterCanvas(
                drawing: player.drawing,
                placements: reduceMotion ? player.restPlacements : player.placements(at: timeline.date))
        }
        .aspectRatio(player.drawing.width / player.drawing.height, contentMode: .fit)
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
                .onTapGesture { try? player.play(PlaceholderCharacter.clip("cheer")) }
        }
    }

    private static func makePlayer() -> CharacterPlayer? {
        try? CharacterPlayer(
            figure: PlaceholderCharacter.figure(wearing: PlaceholderCharacter.lifter),
            idle: PlaceholderCharacter.clip("idle"))
    }
}
#endif
