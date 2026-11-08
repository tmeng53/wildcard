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
    /// White on a graphite card.
    var onInk = false
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
            Text(verbatim: coach.name)
                .typeStyle(name)
                .foregroundStyle(Color(role: onInk ? .fgOnBrand : .fgDefault, in: theme))
                .lineLimit(1)
            Text(verbatim: coach.title)
                .typeStyle(title)
                .foregroundStyle(Color(role: onInk ? .fgOnInkMuted : .fgMuted, in: theme))
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A coach's 简历 fields, 履历, 执教, 风格 and 期望待遇, with a hairline over each row and under the
/// last; each name keeps one line and the names' column grows to the longest. On a page (its 简历)
/// or on ink (the back of its card, smaller and with `valueLines` so the card never overflows).
struct CoachResumeFields: View {
    let coach: Coach
    var onInk = false
    /// The most lines a value takes; nil for as many as it needs.
    var valueLines: Int?
    /// Each name's accessibility identifier, for the UI tests that keep them on one line.
    let labelIdentifier: String
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Space.m, verticalSpacing: 0) {
            row(Text("履历", bundle: .module)) { Text(verbatim: coach.background) }
            row(Text("执教", bundle: .module)) {
                HStack(alignment: .firstTextBaseline, spacing: Space.xxs) {
                    Text(verbatim: "\(coach.yearsCoaching)").typeStyle(TypeRamp.scoreSmall)
                    Text("年，\(coach.experience)", bundle: .module)
                }
            }
            row(Text("风格", bundle: .module)) { Text(verbatim: coach.style) }
            row(Text("期望待遇", bundle: .module)) { Text(verbatim: coach.pay) }
            hairline
        }
    }

    private func row(_ label: Text, @ViewBuilder value: () -> some View) -> some View {
        Group {
            hairline
            GridRow {
                label
                    .typeStyle(onInk ? TypeRamp.label : TypeRamp.body)
                    .foregroundStyle(Color(role: onInk ? .fgOnInkMuted : .fgMuted, in: theme))
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.vertical, Space.s - 1)
                    .accessibilityIdentifier(labelIdentifier)
                value()
                    .typeStyle(onInk ? TypeRamp.callout : TypeRamp.body)
                    .foregroundStyle(Color(role: onInk ? .fgOnInk : .fgDefault, in: theme))
                    .lineLimit(valueLines)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, Space.s - 1)
            }
        }
    }

    private var hairline: some View {
        Hairline(on: onInk ? .ink : .page)
            .gridCellColumns(2)
            .gridCellUnsizedAxes(.horizontal)
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

/// The coach standing on its stage, its line in a bubble right over its head.
struct CoachStage: View {
    let coach: CoachID
    let catchphrase: String
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
            VStack(spacing: Space.s) {
                speech
                figure
            }
            .padding(.horizontal, Space.s + 2)
            .padding(.bottom, floor * CoachMetrics.feet)
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

#endif
