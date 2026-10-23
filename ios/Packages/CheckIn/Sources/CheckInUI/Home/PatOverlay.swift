#if os(iOS)
import AvatarArt
import CheckInDomain
import Contracts
import DesignSystem
import DesignSystemUI
import SwiftUI

/// What 拍一拍 draws over the scene: the bubble over a tapped teammate, and while a pat plays,
/// the accent dot flying from the hand, the 「!」 and the little flick lines where it lands, and
/// the dot resting by their feet for a moment. Positions follow people who move, every frame.
struct PatOverlay: View {
    /// The marks go on the scene, under the squad card; the bubble goes over the card, as in
    /// the approved design, so a teammate at the back still gets a whole bubble to tap.
    enum Layer {
        case marks
        case bubble
    }

    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let layer: Layer
    let cast: SquadCast
    let pats: PatStage
    let unit: Double
    let canPat: (MemberID) -> Bool
    let pat: (MemberID) -> Void

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: pats.pat == nil && pats.bubble == nil)) { timeline in
            let seconds = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            ZStack(alignment: .topLeading) {
                if layer == .marks, let current = pats.pat, !reduceMotion {
                    effects(of: current, at: timeline.date, seconds: seconds)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                if layer == .bubble, let bubble = pats.bubble,
                    let mate = cast.mates.first(where: { $0.id == bubble.mate }),
                    let position = cast.stage.position(of: mate.id, at: seconds)
                {
                    bubbleView(bubble, over: position)
                        .id(bubble.id)
                        .transition(.speech(reduceMotion: reduceMotion))
                }
            }
            .frame(width: StageLayout.width * unit, height: Stage.height * unit, alignment: .topLeading)
            .animation(.wildcard(Motion.sheet, reduceMotion: reduceMotion), value: pats.bubble)
        }
    }

    // MARK: The bubble

    /// The bubble over a teammate's head, slid in just enough to stay on screen, kept clear of
    /// the status bar.
    private func bubbleView(_ bubble: PatStage.Bubble, over position: StagePosition) -> some View {
        let head = position.point.x * unit
        let patted = !canPat(bubble.mate)
        return Color.clear
            .frame(width: 0, height: 0)
            .overlay(alignment: .bottom) {
                SpeechBubble(
                    Text(verbatim: bubble.title),
                    kind: .status(
                        detail: bubble.detail.map { Text(verbatim: $0) },
                        button: .init(
                            patted ? Text("拍过了", bundle: .module) : Text("拍一拍", bundle: .module),
                            isDone: patted, identifier: "today.pat"
                        ) { pat(bubble.mate) })
                )
                .fixedSize()
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("today.patBubble")
                .alignmentGuide(HorizontalAlignment.center) { size in
                    size.width / 2 + head - Self.centre(of: size.width, over: head, unit: unit)
                }
            }
            .position(x: head, y: (position.point.y - Self.headHeight * position.scale) * unit - Space.xs)
    }

    /// How far above the feet a bubble's tail ends, in the rig's points: just over the head.
    private static let headHeight = 250.0

    /// Where a bubble `width` wide centres over a `head`, kept on the stage's width.
    private static func centre(of width: Double, over head: Double, unit: Double) -> Double {
        let stage = StageLayout.width * unit
        return min(max(head, width / 2 + Space.xs), stage - width / 2 - Space.xs)
    }

    // MARK: The pat's marks

    /// Where someone stands this frame and how big they are.
    private func spot(of figure: PatStage.Figure, seconds: Double) -> StagePosition? {
        switch figure {
        case .mine: .mine
        case .mate(let id): cast.stage.position(of: id, at: seconds)
        }
    }

    /// The approved marks, timed from the pat's start, in the design's stage points.
    private func effects(of pat: PatStage.Pat, at date: Date, seconds: Double) -> some View {
        let elapsed = date.timeIntervalSince(pat.start)
        let colors = PatMarks.Colors(
            dot: Color(role: .bgAccent, in: theme), ink: Color(role: .fgDefault, in: theme),
            paper: Color(role: .bgCanvas, in: theme), flick: Color(role: .fgMuted, in: theme))
        return Canvas { context, _ in
            guard let patter = spot(of: pat.patter, seconds: seconds),
                let patted = spot(of: pat.patted, seconds: seconds)
            else { return }
            let marks = PatMarks(patter: patter, patted: patted, unit: unit, colors: colors)
            marks.drawFlight(in: context, elapsed: elapsed)
            let landed = elapsed - PatStage.dotLands
            guard landed >= 0 else { return }
            marks.drawRestingDot(in: context, landed: landed)
            marks.drawBang(in: context, landed: landed)
            marks.drawFlicks(in: context, landed: landed)
        }
        .frame(width: StageLayout.width * unit, height: Stage.height * unit)
    }
}

/// The pat's marks between two people, drawn at a moment of the pat, as the approved design
/// times and places them.
private struct PatMarks {
    struct Colors {
        let dot: Color
        let ink: Color
        let paper: Color
        let flick: Color
    }

    let patter: StagePosition
    let patted: StagePosition
    let unit: Double
    let colors: Colors

    /// 1 when the patted one stands to the right of the patter, else -1.
    private var direction: Double { patted.point.x >= patter.point.x ? 1 : -1 }

    private func point(_ across: Double, _ down: Double) -> CGPoint {
        CGPoint(x: across * unit, y: down * unit)
    }

    private func drawDot(in context: GraphicsContext, at centre: CGPoint, opacity: Double = 1) {
        let radius = 5.5 * unit
        let circle = Path(
            ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: 2 * radius, height: 2 * radius))
        var layer = context
        layer.opacity = opacity
        layer.fill(circle, with: .color(colors.dot))
        layer.stroke(circle, with: .color(colors.ink), lineWidth: 2.2 * unit)
    }

    /// The dot flying over in an arc, from the patter's hand to the patted one.
    func drawFlight(in context: GraphicsContext, elapsed: Double) {
        let flight = (elapsed - PatStage.dotLeaves) / (PatStage.dotLands - PatStage.dotLeaves)
        guard flight > 0, flight < 1 else { return }
        let fromAcross = patter.point.x + direction * 40 * patter.scale / 0.25
        let fromDown = patter.point.y - 160 * patter.scale
        let toDown = patted.point.y - 150 * patted.scale
        drawDot(
            in: context,
            at: point(
                fromAcross + (patted.point.x - fromAcross) * flight,
                fromDown + (toDown - fromDown) * flight - sin(flight * .pi) * 60))
    }

    /// The dot resting on the ground on the patter's side of them, then fading.
    func drawRestingDot(in context: GraphicsContext, landed: Double) {
        guard landed < 1.8 else { return }
        drawDot(
            in: context, at: point(patted.point.x - direction * 70 * patted.scale, patted.point.y - 6),
            opacity: landed > 1.3 ? (1.8 - landed) / 0.5 : 1)
    }

    /// The 「!」 popping over their head: ink on a paper outline, so it reads on any floor.
    func drawBang(in context: GraphicsContext, landed: Double) {
        guard landed < 0.9 else { return }
        let size = min(1, landed * 8) * (landed < 0.15 ? 1.25 - landed : 1)
        var bang = context
        bang.opacity = landed > 0.6 ? (0.9 - landed) / 0.3 : 1
        bang.translateBy(
            x: (patted.point.x + 30 * patted.scale / 0.25 * direction) * unit,
            y: (patted.point.y - 262 * patted.scale) * unit)
        bang.scaleBy(x: size, y: size)
        let mark = Text(verbatim: "!").font(.wildcard(TypeRamp.scoreCard))
        let outline = 2 * unit
        let around = [(-1.0, 0.0), (1, 0), (0, -1), (0, 1), (-0.7, -0.7), (0.7, -0.7), (-0.7, 0.7), (0.7, 0.7)]
        for offset in around {
            bang.draw(
                mark.foregroundStyle(colors.paper), at: CGPoint(x: offset.0 * outline, y: offset.1 * outline))
        }
        bang.draw(mark.foregroundStyle(colors.ink), at: .zero)
    }

    /// Three little flick lines where the dot lands.
    func drawFlicks(in context: GraphicsContext, landed: Double) {
        guard landed < 0.3 else { return }
        let centre = point(
            patted.point.x - direction * 30 * patted.scale / 0.25, patted.point.y - 150 * patted.scale)
        let inner = (6 + landed * 40) * unit
        let outer = inner + 7 * unit
        var flicks = Path()
        for angle in [-0.9, 0, 0.9] {
            let ray = angle - .pi / 2
            flicks.move(to: CGPoint(x: centre.x + cos(ray) * inner, y: centre.y + sin(ray) * inner))
            flicks.addLine(to: CGPoint(x: centre.x + cos(ray) * outer, y: centre.y + sin(ray) * outer))
        }
        var layer = context
        layer.opacity = 1 - landed / 0.3
        layer.stroke(flicks, with: .color(colors.flick), style: StrokeStyle(lineWidth: 2.4 * unit, lineCap: .round))
    }
}
#endif
