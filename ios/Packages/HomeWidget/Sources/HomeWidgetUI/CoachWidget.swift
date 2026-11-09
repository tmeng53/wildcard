#if canImport(SwiftUI)
import AvatarArt
import AvatarDomain
import AvatarUI
import Contracts
import DesignSystem
import DesignSystemUI
import HomeWidgetDomain
import SwiftUI

/// 教练对你说, the medium widget's coach face: the coach peeking in from the corner, what it says
/// to me today and the day's challenge, answered in place. `action` is the challenge's button,
/// which the extension makes from an App Intent (the app's preview passes a plain one).
public struct CoachWidget<Action: View>: View {
    @Environment(\.sceneTheme) private var theme
    private let face: CoachFace
    private let action: (CoachFace.Challenge) -> Action

    public init(face: CoachFace, @ViewBuilder action: @escaping (CoachFace.Challenge) -> Action) {
        self.face = face
        self.action = action
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            HStack(spacing: Space.xxs) {
                Text(verbatim: face.coach.name)
                    .typeStyle(TypeRamp.label)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                if face.hasNews {
                    Circle()
                        .fill(Color(role: .fgDefault, in: theme))
                        .frame(width: WidgetMetrics.dot, height: WidgetMetrics.dot)
                        .accessibilityLabel(Text("有新卡片", bundle: .module))
                }
            }
            .lineLimit(1)
            Group {
                if let line = face.line {
                    Text(verbatim: line)
                } else {
                    Text("今天还没说话", bundle: .module)
                }
            }
            .typeStyle(TypeRamp.callout)
            .foregroundStyle(Color(role: face.line == nil ? .fgMuted : .fgDefault, in: theme))
            .lineLimit(3)
            .accessibilityIdentifier("widget.coachLine")
            Spacer(minLength: Space.xxs)
            if let challenge = face.challenge { row(challenge) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.trailing, WidgetMetrics.coachPeek - WidgetMetrics.coachOverlap)
        .background(alignment: .bottomTrailing) {
            WidgetCoachFigure(coach: face.coach.id)
                .frame(width: WidgetMetrics.coachPeek)
                .offset(x: WidgetMetrics.coachOverlap, y: WidgetMetrics.coachDrop)
        }
    }

    /// 今日挑战 · what to do, and 接受, 完成 or 完成了.
    private func row(_ challenge: CoachFace.Challenge) -> some View {
        HStack(spacing: Space.xs) {
            Text("今日挑战 · \(challenge.title)", bundle: .module)
                .typeStyle(TypeRamp.footnote)
                .foregroundStyle(Color(role: .fgMuted, in: theme))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if challenge.step == .done {
                Label {
                    Text("完成了", bundle: .module)
                } icon: {
                    Image(systemName: "checkmark")
                }
                .typeStyle(TypeRamp.footnoteEmphasis)
                .foregroundStyle(Color(role: .fgAccent, in: theme))
                .lineLimit(1)
            } else {
                action(challenge)
                    .accessibilityIdentifier("widget.challenge")
            }
        }
        .frame(height: WidgetMetrics.challengeButton)
        .accessibilityElement(children: .contain)
    }
}

/// The ink capsule a widget's challenge button wears: 接受 until accepted, then 完成.
public struct ChallengeButtonLabel: View {
    @Environment(\.sceneTheme) private var theme
    private let step: ChallengeStep

    public init(step: ChallengeStep) {
        self.step = step
    }

    public var body: some View {
        Group {
            switch step {
            case .open: Text("接受", bundle: .module)
            case .accepted, .done: Text("完成", bundle: .module)
            }
        }
        .typeStyle(TypeRamp.footnoteEmphasis)
        .foregroundStyle(Color(role: .fgOnInk, in: theme))
        .lineLimit(1)
        .padding(.horizontal, Space.s)
        .frame(height: WidgetMetrics.challengeButton)
        .background(Color(role: .bgInk, in: theme), in: Capsule())
    }
}

/// A coach standing still, drawn now (a widget runs no tasks), down to its waist; nothing for a
/// coach this build has no art for.
struct WidgetCoachFigure: View {
    let coach: CoachID

    var body: some View {
        if let player = Self.player(of: coach) {
            let frame = player.restFrame
            CharacterCanvas(drawing: frame.drawing, placements: frame.placements, crop: Self.crop)
                .aspectRatio(Self.crop.width / Self.crop.height, contentMode: .fit)
                .accessibilityHidden(true)
        }
    }

    /// Head to waist on the coach's 240 × 320 canvas.
    static let crop = CGRect(x: 0, y: 24, width: 240, height: 216)

    static func player(of coach: CoachID) -> CharacterPlayer? {
        let id = coach.rawValue
        guard CoachCharacter.exists(id) else { return nil }
        return try? CharacterPlayer(figure: CoachCharacter.figure(id), idle: CoachCharacter.clip(.idle, coach: id))
    }
}
#endif
