#if os(iOS)
import AvatarUI
import CheckInDomain
import Contracts
import DesignSystem
import DesignSystemUI
import SwiftUI

/// The squad's coach standing on the sideline, member-size, idling; it has no ring, since it
/// doesn't check in.
struct SidelineCoachFigure: View {
    let coach: SquadCast.Coach
    let unit: Double
    let date: Date
    let reduceMotion: Bool

    /// The coaches' canvas, as members', and where its feet are on it.
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
                    .offset(y: (Self.reach.midY - Self.canvas.height / 2) * scale)
                    .allowsHitTesting(false)
            }
            .frame(width: Self.canvas.width * scale, height: Self.canvas.height * scale)
            .contentShape(Rectangle())
            .position(
                x: coach.spot.x * unit,
                y: coach.spot.y * unit - (Self.feet.y - Self.canvas.height / 2) * scale)
    }
}

/// The coach's 战术板 line over its head, the bubble's tail by the screen's edge pointing down
/// at it; it pops in and fades like every bubble on the scene.
struct CoachBubble: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let coach: SquadCast.Coach
    let line: CoachNote?
    let unit: Double

    /// Just over the top of the coach's head, in rig points on its canvas.
    private static let headTop = 24.0

    var body: some View {
        let scale = coach.scale * unit
        Color.clear
            .frame(width: 0, height: 0)
            .overlay(alignment: .bottomLeading) {
                if let line {
                    SpeechBubble(
                        Text(verbatim: line.text), kind: .coach(name: Text(verbatim: coach.speaker.name)),
                        tail: .leading
                    )
                    .fixedSize()
                    .offset(x: -SpeechBubble.leadingTail)
                    .id(line.writtenAt)
                    .transition(.speech(reduceMotion: reduceMotion))
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("today.coachLine")
                }
            }
            .position(
                x: coach.spot.x * unit,
                y: coach.spot.y * unit - (SidelineCoachFigure.feet.y - Self.headTop) * scale
            )
            .allowsHitTesting(false)
    }
}
#endif
