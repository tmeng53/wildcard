#if canImport(SwiftUI)
import AvatarArt
import AvatarDomain
import SwiftUI

/// Where a coach is drawn on its 240 × 320 canvas.
public enum CoachCanvas {
    /// The whole canvas, feet on its bottom edge (a still on a card).
    public static let full = CGRect(x: 0, y: 0, width: 240, height: 320)
    /// The figure with room above for its hop and swaying head (a stage).
    public static let stage = CGRect(x: 36, y: 24, width: 168, height: 296)
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
        .task(id: pose) {
            guard CoachCharacter.exists(coach) else { return }
            player = try? CharacterPlayer(
                figure: CoachCharacter.figure(coach),
                idle: CoachCharacter.clip(pose == .crying ? .crying : .idle, coach: coach))
            if greets, pose == .idle { try? player?.play(CoachCharacter.clip(.cheer, coach: coach)) }
        }
    }
}
#endif
