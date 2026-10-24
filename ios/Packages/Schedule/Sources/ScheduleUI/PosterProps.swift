#if os(iOS)
import DesignSystem
import SwiftUI

/// Two or three of the scene's own things drawn flat in white behind the poster, so it isn't
/// only lines: the gym's dumbbell, kettlebell and plate; the court's racket and balls; the pool's
/// ring, duck and bubbles; the track's hurdle, cone and baton; the wall's carabiner, chalk bag
/// and hold. One sits right of the week's number, the rest right of the first lanes, clear of
/// the lanes' words and the character. Their details are cut out, so the scene shows through.
/// Positions from the approved design, in poster points.
enum PosterProps {
    /// How a part is inked: in the poster's ink, or cut out of what is already drawn.
    enum Ink: Sendable {
        case fill
        case stroke(Double)
        case cut
        case cutStroke(Double)
    }

    struct Part: Sendable {
        let path: Path
        let ink: Ink
    }

    struct Prop: Sendable {
        let center: CGPoint
        var degrees: Double = 0
        var scale: Double = 1
        let parts: [Part]
    }

    static func props(for theme: SceneTheme) -> [Prop] {
        switch theme {
        case .gym: [dumbbell, kettlebell, plate]
        case .tennis:
            [racket, ball(at: CGPoint(x: 302, y: 204), scale: 1), ball(at: CGPoint(x: 250, y: 240), scale: 0.62)]
        case .pool: [ring, duck, bubbles]
        case .track: [hurdle, cone, baton]
        case .climbing: [carabiner, chalkBag, hold]
        }
    }

    /// Draws the props into one layer, in `color` at `opacity`, with each prop's details cut out.
    static func draw(_ props: [Prop], in context: GraphicsContext, color: Color, opacity: Double) {
        let shading = GraphicsContext.Shading.color(color)
        context.drawLayer { layer in
            layer.opacity = opacity
            for prop in props {
                var local = layer
                local.translateBy(x: prop.center.x, y: prop.center.y)
                local.rotate(by: .degrees(prop.degrees))
                local.scaleBy(x: prop.scale, y: prop.scale)
                for part in prop.parts {
                    ink(part, with: shading, in: &local)
                }
            }
        }
    }

    private static func ink(_ part: Part, with shading: GraphicsContext.Shading, in context: inout GraphicsContext) {
        switch part.ink {
        case .fill:
            context.blendMode = .normal
            context.fill(part.path, with: shading)
        case .stroke(let width):
            context.blendMode = .normal
            context.stroke(part.path, with: shading, style: line(width))
        case .cut:
            context.blendMode = .destinationOut
            context.fill(part.path, with: shading)
        case .cutStroke(let width):
            context.blendMode = .destinationOut
            context.stroke(part.path, with: shading, style: line(width))
        }
    }

    private static func line(_ width: Double) -> StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
    }

    // MARK: Shapes

    static func rect(
        _ left: Double, _ top: Double, _ width: Double, _ height: Double, radius: Double = 0
    ) -> Path {
        Path(roundedRect: CGRect(x: left, y: top, width: width, height: height), cornerRadius: radius)
    }

    static func circle(_ centerX: Double, _ centerY: Double, _ radius: Double) -> Path {
        Path(ellipseIn: CGRect(x: centerX - radius, y: centerY - radius, width: radius * 2, height: radius * 2))
    }

    static func ellipse(_ centerX: Double, _ centerY: Double, _ radiusX: Double, _ radiusY: Double) -> Path {
        Path(ellipseIn: CGRect(x: centerX - radiusX, y: centerY - radiusY, width: radiusX * 2, height: radiusY * 2))
    }

    static func lines(_ segments: [(CGPoint, CGPoint)]) -> Path {
        var path = Path()
        for (start, end) in segments {
            path.move(to: start)
            path.addLine(to: end)
        }
        return path
    }

    static func polygon(_ points: [CGPoint]) -> Path {
        var path = Path()
        path.addLines(points)
        path.closeSubpath()
        return path
    }
}
#endif
