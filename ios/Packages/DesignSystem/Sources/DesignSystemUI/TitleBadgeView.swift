#if canImport(SwiftUI)
import DesignSystem
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// A 头衔徽章, as the approved badge board draws it: an enamel pin in a scene's colour (a darker
/// rim, the enamel, a fine white ring and a highlight) with a white SF Symbol on it. Any size;
/// the parts scale with it. A shape this build doesn't draw is a circle, a colour it doesn't know
/// is the gym's, and a glyph this iOS doesn't have is a star, so the API can name new ones.
public struct TitleBadgeView: View {
    /// The shapes this build draws, by the names the API sends.
    public enum Shape: String, Sendable, CaseIterable {
        case shield, hexagon, circle, scallop
    }

    private let shape: Shape
    private let colors: BadgeColors
    private let glyph: String
    private let size: Double

    /// - Parameters:
    ///   - shape: its shape's name (`shield`).
    ///   - colour: the scene whose colour it takes, by id (`track`).
    ///   - glyph: an SF Symbol's name.
    public init(shape: String, colour: String, glyph: String, size: Double) {
        self.shape = Shape(rawValue: shape) ?? .circle
        self.colors = BadgeColors(scene: SceneTheme(rawValue: colour) ?? .gym)
        self.glyph = Self.symbol(glyph)
        self.size = size
    }

    public var body: some View {
        let outline = BadgeOutline(shape: shape)
        ZStack {
            outline.fill(Color(colors.rim))
            outline.fill(Color(colors.enamel)).scaleEffect(Self.enamelScale)
            outline
                .stroke(Color(role: .fgOnInk, in: .gym).opacity(0.6), lineWidth: max(1, size / 44))
                .scaleEffect(Self.ringScale)
            Highlight()
                .stroke(
                    Color(role: .fgOnInk, in: .gym).opacity(0.35),
                    style: StrokeStyle(lineWidth: max(1, size / 24), lineCap: .round))
            Image(systemName: glyph)
                .font(.system(size: size * Self.glyphScale, weight: .semibold))
                .foregroundStyle(Color(role: .fgOnInk, in: .gym))
                .offset(y: shape == .shield ? -size * 0.02 : 0)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// The enamel's colour of a badge in `colour`, for what is drawn beside it (the card's bar
    /// under the number, the top of its detail).
    public static func enamel(_ colour: String) -> Color {
        Color(BadgeColors(scene: SceneTheme(rawValue: colour) ?? .gym).enamel)
    }

    private static let enamelScale = 0.86
    private static let ringScale = 0.72
    private static let glyphScale = 0.36

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

/// The enamel's highlight: a short arc near the top left, as light catching the pin.
private struct Highlight: Shape {
    func path(in rect: CGRect) -> Path {
        let unit = min(rect.width, rect.height) / 48
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 12 * unit, y: rect.minY + 15.5 * unit))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + 26 * unit, y: rect.minY + 8 * unit),
            control: CGPoint(x: rect.minX + 18 * unit, y: rect.minY + 9 * unit))
        return path
    }
}
#endif
