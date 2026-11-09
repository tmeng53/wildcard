#if canImport(SwiftUI)
import DesignSystem
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// A 头衔徽章, the approved 软糖厚章 (2026-11-07): a thick, rounded badge in one colour, built from
/// flat tones (its side showing below, a lit edge at the top left, a shaded one at the bottom
/// right, a highlight) with a white SF Symbol pressed into it, and no gradient or glow. Any
/// size: the badge and its thickness fit the `size` square. A shape this build doesn't draw is a
/// circle, a colour without a tone is its scene's (else the gym's), and a glyph this iOS doesn't
/// have is a star, so the API can name new ones.
public struct TitleBadgeView: View {
    /// The shapes this build draws, by the names the API sends.
    public enum Shape: String, Sendable, CaseIterable {
        case shield, hexagon, circle, scallop
        /// The Wildcard team's dedicated badges (捉虫队, 点子王), never a weekly title's: a ticket
        /// with a notch in each side, so they read apart from the titles on the board.
        case ticket
    }

    private let shape: Shape
    private let colors: BadgeColors
    private let glyph: String
    private let size: Double

    /// - Parameters:
    ///   - shape: its shape's name (`shield`).
    ///   - colour: its colour's id in the badge catalog (`track`).
    ///   - tone: that colour as `#RRGGBB`, when the server sent it.
    ///   - glyph: an SF Symbol's name.
    public init(shape: String, colour: String, tone: String?, glyph: String, size: Double) {
        self.shape = Shape(rawValue: shape) ?? .circle
        self.colors = BadgeColors(colour: colour, tone: tone)
        self.glyph = Self.symbol(glyph)
        self.size = size
    }

    public var body: some View {
        let unit = size / (Self.face + Self.depth)
        let square = Self.face * unit
        let outline = BadgeOutline(shape: shape)
        ZStack(alignment: .top) {
            outline.fill(Color(colors.side)).frame(width: square, height: square).offset(y: Self.depth * unit)
            outline.fill(Color(colors.face)).frame(width: square, height: square)
            outline.fill(Color(colors.lit)).frame(width: square, height: square)
                .scaleEffect(Self.topScale)
                .offset(x: -Self.edge * unit, y: -Self.edge * unit)
            outline.fill(Color(colors.shade)).frame(width: square, height: square)
                .scaleEffect(Self.topScale)
                .offset(x: Self.edge * Self.shadeShare * unit, y: Self.edge * Self.shadeShare * unit)
            outline.fill(Color(colors.face)).frame(width: square, height: square).scaleEffect(Self.topScale)
            Highlight()
                .stroke(
                    Color(role: .fgOnInk, in: .gym).opacity(Self.highlightOpacity),
                    style: StrokeStyle(lineWidth: Self.highlightWidth * unit, lineCap: .round)
                )
                .frame(width: square, height: square)
            glyphImage(Color(colors.side))
                .offset(y: Self.glyphDrop * unit)
            glyphImage(Color(role: .fgOnInk, in: .gym))
        }
        .frame(width: size, height: size, alignment: .top)
        .accessibilityHidden(true)
    }

    private func glyphImage(_ color: Color) -> some View {
        let unit = size / (Self.face + Self.depth)
        return Image(systemName: glyph)
            .font(.system(size: Self.face * unit * Self.glyphScale, weight: .bold))
            .foregroundStyle(color)
            .frame(width: Self.face * unit, height: Self.face * unit)
            .offset(y: shape == .shield ? -unit : 0)
    }

    /// The colour of a badge's face, for what is drawn beside it (the card's bar under the
    /// number, the top of its detail).
    public static func faceColor(colour: String, tone: String?) -> Color {
        Color(BadgeColors(colour: colour, tone: tone).face)
    }

    /// The face's square and the thickness under it, in the outline's 48 units.
    private static let face = 48.0
    private static let depth = 4.2
    /// How far the lit edge shows past the top, and how much of that the shaded one shows.
    private static let edge = 1.1
    private static let shadeShare = 0.7
    private static let topScale = 0.8
    private static let highlightOpacity = 0.6
    private static let highlightWidth = 2.6
    private static let glyphScale = 0.4
    private static let glyphDrop = 1.1

    /// `name` when this iOS has the symbol, else a star.
    private static func symbol(_ name: String) -> String {
        #if canImport(UIKit)
        UIImage(systemName: name) == nil ? "star.fill" : name
        #else
        name
        #endif
    }
}

/// A badge's outline in its square, from the approved board's 48-point drawings.
private struct BadgeOutline: Shape {
    let shape: TitleBadgeView.Shape

    func path(in rect: CGRect) -> Path {
        let unit = min(rect.width, rect.height) / 48
        func point(_ across: Double, _ down: Double) -> CGPoint {
            CGPoint(x: rect.minX + across * unit, y: rect.minY + down * unit)
        }
        var path = Path()
        switch shape {
        case .shield:
            path.move(to: point(24, 2))
            path.addLine(to: point(44, 9))
            path.addLine(to: point(44, 24))
            path.addCurve(to: point(24, 46), control1: point(44, 36), control2: point(34, 44))
            path.addCurve(to: point(4, 24), control1: point(14, 44), control2: point(4, 36))
            path.addLine(to: point(4, 9))
            path.closeSubpath()
        case .hexagon:
            path.addLines([point(24, 2), point(43, 13), point(43, 35), point(24, 46), point(5, 35), point(5, 13)])
            path.closeSubpath()
        case .circle:
            path.addEllipse(in: CGRect(origin: point(2, 2), size: CGSize(width: 44 * unit, height: 44 * unit)))
        case .ticket:
            // A ticket lying across the square, a half-round notch punched in each side.
            let ticket = CGRect(origin: point(2, 9), size: CGSize(width: 44 * unit, height: 30 * unit))
            path.addRoundedRect(
                in: ticket, cornerSize: CGSize(width: 6 * unit, height: 6 * unit), style: .continuous)
            var notches = Path()
            for side in [ticket.minX, ticket.maxX] {
                notches.addEllipse(
                    in: CGRect(x: side - 5 * unit, y: ticket.midY - 5 * unit, width: 10 * unit, height: 10 * unit))
            }
            path = path.subtracting(notches)
        case .scallop:
            // Twelve round bumps around the edge, like a rosette.
            let bumps = 12
            let (outer, inner) = (23.0, 20.0)
            for index in 0..<bumps {
                let start = Double(index) / Double(bumps) * 2 * .pi
                let mid = start + .pi / Double(bumps)
                let end = start + 2 * .pi / Double(bumps)
                let from = point(24 + inner * cos(start), 24 + inner * sin(start))
                if index == 0 { path.move(to: from) }
                path.addQuadCurve(
                    to: point(24 + inner * cos(end), 24 + inner * sin(end)),
                    control: point(24 + (2 * outer - inner) * cos(mid), 24 + (2 * outer - inner) * sin(mid)))
            }
            path.closeSubpath()
        }
        return path
    }
}

/// The highlight: a short arc near the top left of the face, as light catching it.
private struct Highlight: Shape {
    func path(in rect: CGRect) -> Path {
        let unit = min(rect.width, rect.height) / 48
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 13 * unit, y: rect.minY + 16 * unit))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + 25.5 * unit, y: rect.minY + 9.4 * unit),
            control: CGPoint(x: rect.minX + 18 * unit, y: rect.minY + 10.5 * unit))
        return path
    }
}
#endif
