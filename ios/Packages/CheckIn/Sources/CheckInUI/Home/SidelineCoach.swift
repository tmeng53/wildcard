#if os(iOS)
import AvatarUI
import CheckInDomain
import Contracts
import DesignSystem
import DesignSystemUI
import SwiftUI

/// The squad's coach standing on the sideline, as big as me, idling; it has no ring, since it
/// doesn't check in. It drops in after the squad onto a newly picked scene.
struct SidelineCoachFigure: View {
    let coach: SquadCast.Coach
    let unit: Double
    let date: Date
    let reduceMotion: Bool
    /// How far above its spot it is, in stage points, while it drops in.
    var lift: Double = 0

    /// Members' canvas, which coaches share, and where its feet are on it.
    static let canvas = CGSize(width: 240, height: 320)
    static let feet = CGPoint(x: 120, y: 316)
    /// The room above the canvas its cheer's hop reaches into, in rig points.
    private static let reach = CGRect(x: 0, y: -60, width: 240, height: 380)

    var body: some View {
        let scale = coach.scale * unit
        let frame = reduceMotion ? coach.player.restFrame : coach.player.frame(at: date)
        Color.clear
            .overlay {
                CharacterCanvas(drawing: frame.drawing, placements: frame.placements, crop: Self.reach)
                    .frame(width: Self.reach.width * scale, height: Self.reach.height * scale)
                    .offset(y: (Self.reach.midY - Self.canvas.height / 2) * scale - lift * unit)
                    .allowsHitTesting(false)
            }
            .frame(width: Self.canvas.width * scale, height: Self.canvas.height * scale)
            .contentShape(Rectangle())
            .position(
                x: coach.spot.x * unit,
                y: coach.spot.y * unit - (Self.feet.y - Self.canvas.height / 2) * scale)
    }
}
#endif
