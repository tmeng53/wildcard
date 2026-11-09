#if canImport(SwiftUI)
import AvatarArt
import AvatarDomain
import SwiftUI

/// Where a coach is drawn on its 240 × 320 canvas.
public enum CoachCanvas {
    /// The whole canvas, feet on its bottom edge (a still on a card).
    public static let full = CGRect(x: 0, y: 0, width: 240, height: 320)
    /// The figure with room above for its hop and swaying head (a stage), and the full width: a
    /// coach's tail and elbows reach past the body.
    public static let stage = CGRect(x: 0, y: 24, width: 240, height: 296)
}

/// The one way the app draws an AI coach standing (招聘会, 简历, 解雇, 动态's 战术板): its
/// character from `AvatarArt`, idling, crying (being fired), or still; `greets` plays its cheer
/// once as it appears. For a coach this build has no character for, `placeholder` stands in.
/// The home's sideline coach is drawn by the scene's own timeline, from the same character.
public struct CoachFigure<Placeholder: View>: View {
    public enum Pose: Sendable {
        case idle
        case crying
        case still
    }

    private let coach: String
    private let pose: Pose
    private let greets: Bool
    private let crop: CGRect
    private let placeholder: Placeholder
    @State private var player: CharacterPlayer?

    public init(
        coach: String, pose: Pose = .idle, greets: Bool = false, crop: CGRect = CoachCanvas.stage,
        @ViewBuilder placeholder: () -> Placeholder
    ) {
        self.coach = coach
        self.pose = pose
        self.greets = greets
        self.crop = crop
        self.placeholder = placeholder()
    }

    public var body: some View {
        Group {
            if let player {
                if pose == .still {
                    let frame = player.restFrame
                    CharacterCanvas(drawing: frame.drawing, placements: frame.placements, crop: crop)
                        .aspectRatio(crop.width / crop.height, contentMode: .fit)
                } else {
                    CharacterView(player: player, crop: crop)
                }
            } else if !CoachCharacter.exists(coach) {
                placeholder
            } else {
                Color.clear.aspectRatio(crop.width / crop.height, contentMode: .fit)
            }
        }
        .accessibilityHidden(true)
        .task(id: Key(coach: coach, pose: pose)) {
            guard CoachCharacter.exists(coach) else {
                player = nil
                return
            }
            // Parsed off the main actor, so a page with a coach on it doesn't drop a frame opening.
            let (coach, pose, greets) = (coach, pose, greets)
            guard
                let art = try? await Task.detached(operation: {
                    try CoachArt(
                        figure: CoachCharacter.figure(coach),
                        idle: CoachCharacter.clip(pose == .crying ? .crying : .idle, coach: coach),
                        cheer: greets && pose == .idle ? CoachCharacter.clip(.cheer, coach: coach) : nil)
                }).value
            else { return }
            // Another coach or pose replaced this one while it parsed.
            guard !Task.isCancelled else { return }
            player = try? CharacterPlayer(figure: art.figure, idle: art.idle)
            if let cheer = art.cheer { try? player?.play(cheer) }
        }
    }

    /// What the figure is redrawn for: another coach on the same view, or another pose.
    private struct Key: Hashable {
        let coach: String
        let pose: Pose
    }
}

/// A coach's parsed character, built off the main actor.
private struct CoachArt: Sendable {
    let figure: Figure
    let idle: Clip
    let cheer: Clip?
}
#endif
