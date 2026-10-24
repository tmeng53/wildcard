#if os(iOS)
import SwiftUI

/// Each scene's props, in poster points, from the approved design.
extension PosterProps {
    // MARK: Gym

    static var dumbbell: Prop {
        Prop(
            center: CGPoint(x: 286, y: 84), degrees: -18,
            parts: [
                Part(path: rect(-40, -4, 80, 8, radius: 3), ink: .fill),
                Part(path: rect(-42, -24, 13, 48, radius: 4), ink: .fill),
                Part(path: rect(-29, -17, 9, 34, radius: 3), ink: .fill),
                Part(path: rect(29, -24, 13, 48, radius: 4), ink: .fill),
                Part(path: rect(20, -17, 9, 34, radius: 3), ink: .fill),
                Part(path: rect(-29, -17, 1.5, 34), ink: .cut),
                Part(path: rect(27.5, -17, 1.5, 34), ink: .cut),
            ])
    }

    static var kettlebell: Prop {
        var handle = Path()
        handle.move(to: CGPoint(x: -13, y: -4))
        handle.addCurve(to: CGPoint(x: 13, y: -4), control1: CGPoint(x: -13, y: -30), control2: CGPoint(x: 13, y: -30))
        return Prop(
            center: CGPoint(x: 300, y: 214),
            parts: [
                Part(path: handle, ink: .stroke(7)),
                Part(path: circle(0, 12, 22), ink: .fill),
                Part(path: rect(-14, 30, 28, 5, radius: 2), ink: .fill),
                Part(path: rect(-9, 4, 18, 12, radius: 3), ink: .cut),
            ])
    }

    static var plate: Prop {
        Prop(
            center: CGPoint(x: 244, y: 248),
            parts: [
                Part(path: circle(0, 0, 14), ink: .fill),
                Part(path: circle(0, 0, 9.5), ink: .cutStroke(1.5)),
                Part(path: circle(0, 0, 3.5), ink: .cut),
            ])
    }

    // MARK: Tennis

    static var racket: Prop {
        let across: [(CGPoint, CGPoint)] = [-12.0, 0, 12].map { (CGPoint(x: $0, y: -38), CGPoint(x: $0, y: 22)) }
        let down: [(CGPoint, CGPoint)] = [-22.0, -8, 6].map { (CGPoint(x: -23, y: $0), CGPoint(x: 23, y: $0)) }
        let strings = lines(across + down)
        var throat = Path()
        throat.addLines([CGPoint(x: -11, y: 25), CGPoint(x: 0, y: 42), CGPoint(x: 11, y: 25)])
        return Prop(
            center: CGPoint(x: 292, y: 74), degrees: -32,
            parts: [
                Part(path: ellipse(0, -8, 29, 36), ink: .fill),
                Part(path: ellipse(0, -8, 23, 30), ink: .cut),
                // White on the white frame, so only the part over the hole shows.
                Part(path: strings, ink: .stroke(1.6)),
                Part(path: throat, ink: .stroke(4)),
                Part(path: rect(-5, 40, 10, 40, radius: 4), ink: .fill),
            ])
    }

    static func ball(at center: CGPoint, scale: Double) -> Prop {
        var seams = Path()
        seams.move(to: CGPoint(x: -13, y: -13))
        seams.addCurve(to: CGPoint(x: -13, y: 13), control1: CGPoint(x: -4, y: -5), control2: CGPoint(x: -4, y: 5))
        seams.move(to: CGPoint(x: 13, y: -13))
        seams.addCurve(to: CGPoint(x: 13, y: 13), control1: CGPoint(x: 4, y: -5), control2: CGPoint(x: 4, y: 5))
        return Prop(
            center: center, scale: scale,
            parts: [
                Part(path: circle(0, 0, 19), ink: .fill),
                // Thicker on the small ball, so its seams read at the same weight.
                Part(path: seams, ink: .cutStroke(scale < 1 ? 3 : 2.4)),
            ])
    }

    // MARK: Pool

    static var ring: Prop {
        Prop(
            center: CGPoint(x: 290, y: 82), degrees: 20,
            parts: [
                Part(path: circle(0, 0, 33), ink: .fill),
                Part(path: circle(0, 0, 15), ink: .cut),
                Part(
                    path: lines([
                        (CGPoint(x: 0, y: -33), CGPoint(x: 0, y: -15)), (CGPoint(x: 0, y: 15), CGPoint(x: 0, y: 33)),
                        (CGPoint(x: -33, y: 0), CGPoint(x: -15, y: 0)), (CGPoint(x: 15, y: 0), CGPoint(x: 33, y: 0)),
                    ]), ink: .cutStroke(4)),
                // The rope round the ring, a dotted line cut out.
                Part(
                    path: circle(0, 0, 24).strokedPath(StrokeStyle(lineWidth: 1.2, dash: [2, 4])),
                    ink: .cut),
            ])
    }

    static var duck: Prop {
        var wing = Path()
        wing.move(to: CGPoint(x: -12, y: 4))
        wing.addQuadCurve(to: CGPoint(x: 8, y: 5), control: CGPoint(x: -2, y: 14))
        return Prop(
            center: CGPoint(x: 294, y: 214),
            parts: [
                Part(path: ellipse(-2, 8, 24, 14), ink: .fill),
                Part(
                    path: polygon([CGPoint(x: -24, y: 2), CGPoint(x: -32, y: -6), CGPoint(x: -20, y: -2)]), ink: .fill),
                Part(path: circle(12, -10, 11), ink: .fill),
                Part(path: ellipse(25, -8, 7, 3.5), ink: .fill),
                Part(path: circle(15, -12, 2), ink: .cut),
                Part(path: wing, ink: .cutStroke(2)),
            ])
    }

    static var bubbles: Prop {
        Prop(
            center: CGPoint(x: 248, y: 232),
            parts: [
                Part(path: circle(-2, 12, 6), ink: .stroke(2)),
                Part(path: circle(10, -4, 4), ink: .stroke(2)),
                Part(path: circle(-6, -10, 2.5), ink: .stroke(2)),
            ])
    }

    // MARK: Track

    static var hurdle: Prop {
        Prop(
            center: CGPoint(x: 288, y: 84),
            parts: [
                Part(path: rect(-36, -20, 5, 50), ink: .fill),
                Part(path: rect(31, -20, 5, 50), ink: .fill),
                Part(path: rect(-42, 28, 17, 4, radius: 2), ink: .fill),
                Part(path: rect(25, 28, 17, 4, radius: 2), ink: .fill),
                Part(path: rect(-42, -30, 84, 15, radius: 2), ink: .fill),
                Part(path: rect(-26, -30, 13, 15), ink: .cut),
                Part(path: rect(0, -30, 13, 15), ink: .cut),
                Part(path: rect(26, -30, 13, 15), ink: .cut),
            ])
    }

    static var cone: Prop {
        let body = polygon([
            CGPoint(x: -4, y: -30), CGPoint(x: 4, y: -30), CGPoint(x: 17, y: 14), CGPoint(x: -17, y: 14),
        ])
        return Prop(
            center: CGPoint(x: 300, y: 214),
            parts: [
                Part(path: body, ink: .fill),
                Part(path: body, ink: .stroke(2)),
                Part(path: rect(-24, 14, 48, 6, radius: 2), ink: .fill),
                Part(
                    path: polygon([
                        CGPoint(x: -9, y: -9), CGPoint(x: 9, y: -9), CGPoint(x: 11.5, y: -1), CGPoint(x: -11.5, y: -1),
                    ]), ink: .cut),
            ])
    }

    static var baton: Prop {
        Prop(
            center: CGPoint(x: 248, y: 242), degrees: -28,
            parts: [
                Part(path: rect(-18, -4.5, 36, 9, radius: 4.5), ink: .fill),
                Part(path: rect(-6, -4.5, 1.5, 9), ink: .cut),
                Part(path: rect(4.5, -4.5, 1.5, 9), ink: .cut),
            ])
    }

    // MARK: Climbing

    static var carabiner: Prop {
        var body = Path()
        body.move(to: CGPoint(x: -12, y: -34))
        body.addLine(to: CGPoint(x: 8, y: -34))
        body.addQuadCurve(to: CGPoint(x: 23, y: -18), control: CGPoint(x: 24, y: -34))
        body.addLine(to: CGPoint(x: 19, y: 20))
        body.addQuadCurve(to: CGPoint(x: 2, y: 36), control: CGPoint(x: 17, y: 36))
        body.addLine(to: CGPoint(x: -8, y: 36))
        body.addQuadCurve(to: CGPoint(x: -22, y: 22), control: CGPoint(x: -22, y: 36))
        body.addLine(to: CGPoint(x: -22, y: -24))
        body.addQuadCurve(to: CGPoint(x: -12, y: -34), control: CGPoint(x: -22, y: -34))
        body.closeSubpath()
        return Prop(
            center: CGPoint(x: 290, y: 84), degrees: 18,
            parts: [
                Part(path: body, ink: .stroke(7)),
                // The gate: a gap in the spine, and the gate bar swung in across it.
                Part(path: rect(-25.5, -14, 7, 24), ink: .cut),
                Part(path: lines([(CGPoint(x: -22, y: -14), CGPoint(x: -16, y: 10))]), ink: .stroke(4)),
            ])
    }

    static var chalkBag: Prop {
        var drawstring = Path()
        drawstring.move(to: CGPoint(x: 14, y: -10))
        drawstring.addQuadCurve(to: CGPoint(x: 18, y: 10), control: CGPoint(x: 22, y: 0))
        return Prop(
            center: CGPoint(x: 300, y: 218),
            parts: [
                Part(path: rect(-18, -12, 36, 34, radius: 9), ink: .fill),
                Part(path: rect(-21, -21, 42, 11, radius: 4), ink: .fill),
                Part(path: lines([(CGPoint(x: -21, y: -10), CGPoint(x: 21, y: -10))]), ink: .cutStroke(2)),
                Part(path: drawstring, ink: .cutStroke(1.6)),
                Part(path: circle(-6, -30, 4), ink: .fill),
                Part(path: circle(5, -34, 3), ink: .fill),
                Part(path: circle(-1, -41, 2), ink: .fill),
            ])
    }

    static var hold: Prop {
        var body = Path()
        body.move(to: CGPoint(x: -18, y: -1))
        body.addQuadCurve(to: CGPoint(x: -2, y: -19), control: CGPoint(x: -18, y: -17))
        body.addQuadCurve(to: CGPoint(x: 16, y: -9), control: CGPoint(x: 12, y: -21))
        body.addQuadCurve(to: CGPoint(x: 6, y: 11), control: CGPoint(x: 20, y: 5))
        body.addQuadCurve(to: CGPoint(x: -14, y: 11), control: CGPoint(x: -6, y: 17))
        body.addQuadCurve(to: CGPoint(x: -18, y: -1), control: CGPoint(x: -18, y: 7))
        body.closeSubpath()
        var lip = Path()
        lip.move(to: CGPoint(x: -10, y: -9))
        lip.addQuadCurve(to: CGPoint(x: 10, y: -9), control: CGPoint(x: 0, y: -14))
        return Prop(
            center: CGPoint(x: 250, y: 239),
            parts: [
                Part(path: body, ink: .fill),
                Part(path: lip, ink: .cutStroke(1.6)),
                Part(path: circle(0, 0, 3.2), ink: .cut),
            ])
    }
}
#endif
