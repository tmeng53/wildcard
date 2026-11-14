#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import Contracts
import DesignSystem
import DesignSystemUI
import SwiftUI

/// The squad's coach on 本周出赛表, standing still with its feet behind the challenge card (it
/// never speaks there); a dashed spot with + while the squad has none; nothing for a coach this
/// build has no art for.
struct ScheduleCoach: View {
    @Environment(\.sceneTheme) private var theme
    let coach: CoachID?
    /// The coach's whole canvas, feet at its foot.
    let height: Double

    /// The see-through white of the empty spot's +, and of a rest day's or a 请假条 day's disc.
    nonisolated static let wash: Double = 0.16

    private var onScene: Color { Color(role: .fgOnAccent, in: theme) }

    var body: some View {
        if let coach, let player = WidgetCoach.player(of: coach) {
            let frame = player.restFrame
            CharacterCanvas(drawing: frame.drawing, placements: frame.placements, crop: CoachCanvas.full)
                .frame(width: height * CoachCanvas.full.width / CoachCanvas.full.height, height: height)
                .accessibilityHidden(true)
        } else if coach == nil {
            let width = height * 0.5
            RoundedRectangle(cornerRadius: width / 2)
                .strokeBorder(onScene.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                .frame(width: width, height: height * 0.62)
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: width * 0.28, weight: .bold))
                        .frame(width: width * 0.48, height: width * 0.48)
                        .background(onScene.opacity(Self.wash), in: Circle())
                }
                .padding(.bottom, height * 0.3)
                .accessibilityHidden(true)
        }
    }

}

/// A coach on the widgets, drawn still: a widget is a picture, so nothing plays.
enum WidgetCoach {
    /// The coach standing still; nil for a coach this build has no art for.
    static func player(of coach: CoachID) -> CharacterPlayer? {
        let id = coach.rawValue
        guard CoachCharacter.exists(id) else { return nil }
        return try? CharacterPlayer(figure: CoachCharacter.figure(id), idle: CoachCharacter.clip(.idle, coach: id))
    }
}
#endif
