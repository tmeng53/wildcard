#if os(iOS)
import AvatarArt
import AvatarUI
import Contracts
import DesignSystem
import DesignSystemUI
import SquadDomain
import SwiftUI

// The pieces of the coach's pages: its name and title, its tag, its stage and character.

/// A coach's name with its title beside it, such as 毛头 混混教练.
struct CoachName: View {
    let coach: Coach
    let name: TypeStyle
    let title: TypeStyle
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
            Text(verbatim: coach.name)
                .typeStyle(name)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .lineLimit(1)
            Text(verbatim: coach.title)
                .typeStyle(title)
                .foregroundStyle(Color(role: .fgMuted, in: theme))
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 求职中 on a coach looking for a squad; 你们的教练 on the squad's own.
struct StatusTag: View {
    let isCurrent: Bool

    var body: some View {
        Tag(
            isCurrent ? Text("你们的教练", bundle: .module) : Text("求职中", bundle: .module), style: .ink, size: .small
        )
        .fixedSize()
    }
}

/// The coach standing on its stage, its line in a bubble above.
struct CoachStage: View {
    enum Bubble {
        case leading
        case center
    }

    let coach: CoachID
    let catchphrase: String
    let bubble: Bubble
    let figureHeight: Double
    let floor: Double
    var mood: CoachSilhouette.Mood = .calm
    /// On a grey page block (解雇) the stage is the block's grey; elsewhere a deeper grey.
    var surface: CardSurface = .scene
    /// Cheers once when the stage appears, as on the coach's 简历.
    var greets = false
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(role: surface == .page ? .bgSubtle : .borderDefault, in: theme)
            Color(role: surface == .page ? .borderDefault : .fgSubtle, in: theme)
                .opacity(surface == .page ? 1 : CoachMetrics.floorShade)
                .frame(height: floor)
            switch bubble {
            case .leading:
                // As on the approved card: the line pinned to the stage's top corner, the coach
                // standing under it in the middle.
                figure
                    .padding(.bottom, floor * CoachMetrics.feet)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .overlay(alignment: .topLeading) {
                        speech.padding(Space.s + 2)
                    }
            case .center:
                VStack(spacing: Space.s) {
                    speech
                    figure
                }
                .padding(.horizontal, Space.s + 2)
                .padding(.bottom, floor * CoachMetrics.feet)
            }
        }
    }

    private var speech: some View {
        SpeechBubble(Text(verbatim: catchphrase), kind: .quote, on: .scene)
    }

    private var figure: some View {
        CoachFigure(coach: coach.rawValue, pose: mood == .crying ? .crying : .idle, greets: greets) {
            CoachSilhouette(fill: Color(role: .bgInk, in: theme), mood: mood)
        }
        .frame(height: figureHeight)
    }
}

/// A coach this build has no character for, and 更多教练在路上: an ink silhouette, round on
/// top. Crying, it has two eyes squeezed shut, tears and a frown.
struct CoachSilhouette: View {
    enum Mood {
        case calm
        case crying
    }

    let fill: Color
    var mood: Mood = .calm
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        Canvas { context, size in
            let width = size.width
            let body = UnevenRoundedRectangle(
                topLeadingRadius: width / 2, bottomLeadingRadius: width * 0.09, bottomTrailingRadius: width * 0.09,
                topTrailingRadius: width / 2, style: .continuous
            ).path(in: CGRect(origin: .zero, size: size))
            context.fill(body, with: .color(fill))
            guard mood == .crying else { return }
            // Drawn on the canvas's 92-point-wide figure, scaled.
            let unit = width / 92
            let face = Color(role: .fgOnInk, in: theme)
            let tear = Color(role: .fgOnInkMuted, in: theme)
            for left in [24.0, 56.0] {
                context.fill(
                    Capsule().path(in: CGRect(x: left * unit, y: 40 * unit, width: 12 * unit, height: 4 * unit)),
                    with: .color(face))
            }
            for (left, top) in [(26.0, 50.0), (58.0, 56.0)] {
                context.fill(
                    Path(ellipseIn: CGRect(x: left * unit, y: top * unit, width: 8 * unit, height: 12 * unit)),
                    with: .color(tear))
            }
            var frown = Path()
            frown.move(to: CGPoint(x: 37 * unit, y: 79 * unit))
            frown.addQuadCurve(to: CGPoint(x: 55 * unit, y: 79 * unit), control: CGPoint(x: 46 * unit, y: 68 * unit))
            context.stroke(frown, with: .color(face), style: StrokeStyle(lineWidth: 3 * unit, lineCap: .round))
        }
        .aspectRatio(CoachMetrics.figureAspect, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// The coach's square on 小队设置: its character's head and shoulders (a silhouette for a coach
/// this build can't draw), or a dashed outline while there is none.
struct CoachThumbnail: View {
    /// Nil while the squad has no coach.
    let coach: CoachID?
    @State private var head: CharacterPlayer?
    @Environment(\.sceneTheme) private var theme

    /// The head and shoulders on the 240 × 320 canvas coaches share with members.
    private static let face = CGRect(x: 40, y: 74, width: 160, height: 160)

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(role: .bgCanvas, in: theme)
            if coach == nil {
                UnevenRoundedRectangle(
                    topLeadingRadius: CoachMetrics.thumbnailFigure / 2,
                    topTrailingRadius: CoachMetrics.thumbnailFigure / 2,
                    style: .continuous
                )
                .stroke(Color(role: .fgSubtle, in: theme), style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                .frame(width: CoachMetrics.thumbnailFigure, height: CoachMetrics.thumbnailFigure * 1.7)
                .offset(y: 2)
            } else if let head {
                let frame = head.restFrame
                CharacterCanvas(drawing: frame.drawing, placements: frame.placements, crop: Self.face)
            } else if let coach, !CoachCharacter.exists(coach.rawValue) {
                CoachSilhouette(fill: Color(role: .bgInk, in: theme))
                    .frame(width: CoachMetrics.thumbnailFigure)
            }
        }
        .frame(width: CoachMetrics.thumbnail, height: CoachMetrics.thumbnail)
        .clipShape(RoundedRectangle(cornerRadius: Radius.thumbnail, style: .continuous))
        .accessibilityHidden(true)
        .task(id: coach) {
            head = nil
            guard let id = coach?.rawValue, CoachCharacter.exists(id) else { return }
            head = try? CharacterPlayer(figure: CoachCharacter.figure(id), idle: CoachCharacter.clip(.idle, coach: id))
        }
    }
}

#endif
