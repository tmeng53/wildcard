#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

// swiftlint:disable identifier_name - x and y are the names CGPoint and CGRect use.

/// The kraft carton a new scene arrives in, 170 × 190 points, drawn as the approved scene-pick
/// reveal draws it: tape across the closed flaps, "this way up" arrows and a handle. The caller
/// moves the whole carton; `leftFlap` and `rightFlap` fly each flap off its hinge (moved, then
/// turned, in degrees clockwise) while `flapOpacity` fades them.
public struct CartonBox: View {
    public struct Flap: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var degrees: Double

        public init(x: Double, y: Double, degrees: Double) {
            (self.x, self.y, self.degrees) = (x, y, degrees)
        }

        public static let closed = Flap(x: 0, y: 0, degrees: 0)
    }

    public static let size = CGSize(width: 170, height: 190)
    /// The art's own corners: the carton, its base edge, the handle.
    private static let corner = 8.0
    private static let baseCorner = 6.0
    private static let handleCorner = 3.0

    private let leftFlap: Flap
    private let rightFlap: Flap
    private let flapOpacity: Double

    public init(leftFlap: Flap = .closed, rightFlap: Flap = .closed, flapOpacity: Double = 1) {
        self.leftFlap = leftFlap
        self.rightFlap = rightFlap
        self.flapOpacity = flapOpacity
    }

    public var body: some View {
        Canvas { context, _ in
            Self.drawBody(in: &context)
            var flaps = context
            flaps.opacity = flapOpacity
            Self.drawFlap(
                in: flaps, hinge: CGPoint(x: 8, y: 48), flap: leftFlap,
                shape: [CGPoint(x: 6, y: 48), CGPoint(x: 85, y: 48), CGPoint(x: 85, y: 24), CGPoint(x: 16, y: 24)],
                art: (Palette.kraftFlap, CGRect(x: 73, y: 24, width: 12, height: 24)))
            Self.drawFlap(
                in: flaps, hinge: CGPoint(x: 162, y: 48), flap: rightFlap,
                shape: [CGPoint(x: 85, y: 48), CGPoint(x: 164, y: 48), CGPoint(x: 154, y: 24), CGPoint(x: 85, y: 24)],
                art: (Palette.kraftFlapShade, CGRect(x: 85, y: 24, width: 12, height: 24)))
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .accessibilityHidden(true)
    }

    private static func drawBody(in context: inout GraphicsContext) {
        let round = StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
        context.fill(
            Path(roundedRect: CGRect(x: 6, y: 46, width: 158, height: 144), cornerRadius: Self.corner),
            with: .color(Color(Palette.kraft)))
        context.fill(
            Path(roundedRect: CGRect(x: 6, y: 176, width: 158, height: 14), cornerRadius: Self.baseCorner),
            with: .color(Color(Palette.kraftShade)))
        context.fill(Path(CGRect(x: 73, y: 46, width: 24, height: 64)), with: .color(Color(Palette.kraftTape)))
        // The tape's torn end.
        var torn = Path()
        torn.move(to: CGPoint(x: 73, y: 110))
        for (index, x) in stride(from: 77.0, through: 97, by: 4).enumerated() {
            torn.addLine(to: CGPoint(x: x, y: index.isMultiple(of: 2) ? 107 : 110))
        }
        context.stroke(torn, with: .color(Color(Palette.kraftTape)), lineWidth: 2)
        var arrows = Path()
        for x in [24.0, 40.0] {
            arrows.move(to: CGPoint(x: x, y: 168))
            arrows.addLine(to: CGPoint(x: x, y: 150))
            arrows.move(to: CGPoint(x: x - 6, y: 156))
            arrows.addLine(to: CGPoint(x: x, y: 150))
            arrows.addLine(to: CGPoint(x: x + 6, y: 156))
        }
        context.stroke(arrows, with: .color(Color(Palette.kraftInk)), style: round)
        context.stroke(
            Path(roundedRect: CGRect(x: 128, y: 150, width: 22, height: 18), cornerRadius: Self.handleCorner),
            with: .color(Color(Palette.kraftInk)), lineWidth: 2.5)
        var handle = Path()
        handle.move(to: CGPoint(x: 133, y: 159))
        handle.addLine(to: CGPoint(x: 145, y: 159))
        context.stroke(
            handle, with: .color(Color(Palette.kraftInk)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
    }

    /// A flap as CSS moves it: about `hinge`, turned, then moved.
    private static func drawFlap(
        in context: GraphicsContext, hinge: CGPoint, flap: Flap, shape: [CGPoint], art: (color: SRGBColor, tape: CGRect)
    ) {
        var context = context
        context.transform = CGAffineTransform(translationX: hinge.x + flap.x, y: hinge.y + flap.y)
            .rotated(by: flap.degrees * .pi / 180)
            .translatedBy(x: -hinge.x, y: -hinge.y)
        var outline = Path()
        outline.addLines(shape)
        outline.closeSubpath()
        context.fill(outline, with: .color(Color(art.color)))
        context.fill(Path(art.tape), with: .color(Color(Palette.kraftTape)))
    }
}
// swiftlint:enable identifier_name
#endif
