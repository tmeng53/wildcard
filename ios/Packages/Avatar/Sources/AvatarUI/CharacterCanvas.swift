#if canImport(SwiftUI)
import AvatarDomain
import SwiftUI

/// A figure's art turned into SwiftUI paths once, so drawing a frame only sets transforms
/// and fills.
public struct FigureDrawing {
    public let width: Double
    public let height: Double
    let parts: [[DrawableShape]]

    struct DrawableShape {
        let path: Path
        let fill: Color?
        let stroke: (color: Color, style: StrokeStyle)?
        let opacity: Double
    }

    public init(_ figure: Figure) {
        width = figure.width
        height = figure.height
        parts = figure.parts.map { part in
            part.art.flatMap(\.shapes).map { shape in
                DrawableShape(
                    path: Path(shape.path),
                    fill: shape.fill.map { Color($0) },
                    stroke: shape.stroke.map { stroke in
                        (
                            Color(stroke.color),
                            StrokeStyle(
                                lineWidth: stroke.width, lineCap: CGLineCap(stroke.cap),
                                lineJoin: CGLineJoin(stroke.join))
                        )
                    },
                    opacity: shape.opacity)
            }
        }
    }
}

/// Draws one frame: every part where its placement puts it, scaled to fit the view.
public struct CharacterCanvas: View {
    let drawing: FigureDrawing
    let placements: [Placement]

    public init(drawing: FigureDrawing, placements: [Placement]) {
        self.drawing = drawing
        self.placements = placements
    }

    public var body: some View {
        Canvas { context, size in
            let scale = min(size.width / drawing.width, size.height / drawing.height)
            let fit = CGAffineTransform(scaleX: scale, y: scale).translatedBy(
                x: (size.width / scale - drawing.width) / 2, y: (size.height / scale - drawing.height) / 2)
            for (shapes, placement) in zip(drawing.parts, placements) where placement.opacity > 0 && !shapes.isEmpty {
                var part = context
                part.transform = CGAffineTransform(placement.transform).concatenating(fit)
                guard placement.opacity < 1 else {
                    draw(shapes, in: &part)
                    continue
                }
                // A fading part fades as one piece, so its overlapping shapes don't show through.
                part.opacity = placement.opacity
                part.drawLayer { layer in draw(shapes, in: &layer) }
            }
        }
    }

    private func draw(_ shapes: [FigureDrawing.DrawableShape], in context: inout GraphicsContext) {
        for shape in shapes {
            var each = context
            each.opacity *= shape.opacity
            guard shape.opacity < 1, shape.fill != nil, shape.stroke != nil else {
                paint(shape, in: &each)
                continue
            }
            // As in SVG, fill and stroke fade together, so the stroke doesn't darken the fill under it.
            each.drawLayer { layer in paint(shape, in: &layer) }
        }
    }

    private func paint(_ shape: FigureDrawing.DrawableShape, in context: inout GraphicsContext) {
        if let fill = shape.fill { context.fill(shape.path, with: .color(fill)) }
        if let stroke = shape.stroke { context.stroke(shape.path, with: .color(stroke.color), style: stroke.style) }
    }
}

extension Path {
    init(_ elements: [PathElement]) {
        self.init()
        for element in elements {
            switch element {
            case .move(let point): move(to: CGPoint(point))
            case .line(let end): addLine(to: CGPoint(end))
            case .quadCurve(let end, let control): addQuadCurve(to: CGPoint(end), control: CGPoint(control))
            case .curve(let end, let control1, let control2):
                addCurve(to: CGPoint(end), control1: CGPoint(control1), control2: CGPoint(control2))
            case .close: closeSubpath()
            }
        }
    }
}

extension CGPoint {
    init(_ point: Point) {
        self.init(x: point.x, y: point.y)
    }
}

extension CGAffineTransform {
    init(_ transform: Transform) {
        self.init(
            a: transform.a, b: transform.b, c: transform.c, d: transform.d, tx: transform.tx, ty: transform.ty)
    }
}

extension Color {
    init(_ color: RGBAColor) {
        self.init(
            .sRGB, red: Double(color.red) / 255, green: Double(color.green) / 255, blue: Double(color.blue) / 255,
            opacity: color.opacity)
    }
}

extension CGLineCap {
    init(_ cap: Stroke.Cap) {
        switch cap {
        case .butt: self = .butt
        case .round: self = .round
        case .square: self = .square
        }
    }
}

extension CGLineJoin {
    init(_ join: Stroke.Join) {
        switch join {
        case .miter: self = .miter
        case .round: self = .round
        case .bevel: self = .bevel
        }
    }
}
#endif
