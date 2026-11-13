#if canImport(SwiftUI)
import AvatarDomain
import SwiftUI

/// A figure's art turned into SwiftUI paths once, so drawing a frame only sets transforms
/// and fills.
public struct FigureDrawing {
    public let width: Double
    public let height: Double
    let parts: [[DrawableShape]]
    /// Each part's art as read, kept for an arm, whose paths are rebuilt bent each frame it bends.
    let bendable: [[ArtShape]?]
    /// For an arm tucked behind its body at its seam (`Figure.Part.tuck`): the clip it is
    /// drawn in over the body, and the clip it is drawn in under it, in the arm's own coordinates.
    let tucks: [(over: Path, under: Path)?]
    /// For each part, the tucked arms that hang from it, drawn under it first.
    let tucked: [[Int]]

    struct DrawableShape {
        let path: Path
        let fill: Color?
        let stroke: (color: Color, style: StrokeStyle)?
        let opacity: Double
    }

    public init(_ figure: Figure) {
        width = figure.width
        height = figure.height
        parts = figure.parts.map { part in Self.shapes(part.art.flatMap(\.shapes)) }
        bendable = figure.parts.map { part in part.elbow.map { _ in part.art.flatMap(\.shapes) } }
        let far = figure.width + figure.height
        tucks = figure.parts.map { part in
            part.tuck.map { tuck in
                (
                    over: Path(tuck.seam.kept(reaching: far).map { CGPoint($0) }),
                    under: Path(tuck.under.kept(reaching: far).map { CGPoint($0) })
                )
            }
        }
        tucked = figure.parts.indices.map { body in
            figure.parts.indices.filter { figure.parts[$0].parent == body && figure.parts[$0].tuck != nil }
        }
    }

    /// A part's shapes as `placement` draws them: bent first when it is a bent arm.
    func shapes(_ part: Int, _ placement: Placement) -> [DrawableShape] {
        guard let bend = placement.bend, let art = bendable[part] else { return parts[part] }
        return Self.shapes(
            art.map { shape in
                var bent = shape
                bent.path = bend.apply(to: shape.path)
                return bent
            })
    }

    /// The canvas area the drawing covers in `placements`, strokes included: where a crop
    /// fits a figure wearing one piece only. Nil when nothing shows.
    public func bounds(_ placements: [Placement]) -> CGRect? {
        var covered: CGRect?
        for (shapes, placement) in zip(parts, placements) where placement.opacity > 0 {
            let transform = CGAffineTransform(placement.transform)
            for shape in shapes {
                let width = shape.stroke?.style.lineWidth ?? 0
                let box = shape.path.boundingRect.insetBy(dx: -width / 2, dy: -width / 2).applying(transform)
                covered = covered?.union(box) ?? box
            }
        }
        return covered
    }

    /// Art's shapes as SwiftUI paths and paints.
    static func shapes(_ shapes: [ArtShape]) -> [DrawableShape] {
        shapes.map { shape in
            DrawableShape(
                path: Path(shape.path),
                fill: shape.fill.map { Color($0) },
                stroke: shape.stroke.map { stroke in
                    (
                        Color(stroke.color),
                        StrokeStyle(
                            lineWidth: stroke.width, lineCap: CGLineCap(stroke.cap),
                            lineJoin: CGLineJoin(stroke.join), dash: stroke.dash.map { CGFloat($0) })
                    )
                },
                opacity: shape.opacity)
        }
    }
}

/// Draws one frame: every part where its placement puts it, scaled to fit the view. Pass
/// `crop`, in canvas points, to fit only that part of the canvas, such as the head for a
/// hairstyle thumbnail; what falls outside it is clipped.
public struct CharacterCanvas: View {
    let drawing: FigureDrawing
    let placements: [Placement]
    let crop: CGRect?

    public init(drawing: FigureDrawing, placements: [Placement], crop: CGRect? = nil) {
        self.drawing = drawing
        self.placements = placements
        self.crop = crop
    }

    public var body: some View {
        Canvas { context, size in
            let area = crop ?? CGRect(x: 0, y: 0, width: drawing.width, height: drawing.height)
            let scale = min(size.width / area.width, size.height / area.height)
            let fit = CGAffineTransform(scaleX: scale, y: scale).translatedBy(
                x: (size.width / scale - area.width) / 2 - area.minX,
                y: (size.height / scale - area.height) / 2 - area.minY)
            for index in drawing.parts.indices {
                for arm in drawing.tucked[index] {
                    context.draw(drawing, arm, placements[arm], in: drawing.tucks[arm]?.under, fit: fit)
                }
                context.draw(drawing, index, placements[index], in: drawing.tucks[index]?.over, fit: fit)
            }
        }
    }
}

extension GraphicsContext {
    /// Draws one part as `placement` puts it, inside `clip` (in the part's own coordinates)
    /// when there is one.
    func draw(
        _ drawing: FigureDrawing, _ index: Int, _ placement: Placement, in clip: Path?, fit: CGAffineTransform
    ) {
        guard placement.opacity > 0, !drawing.parts[index].isEmpty else { return }
        let shapes = drawing.shapes(index, placement)
        var part = self
        part.transform = CGAffineTransform(placement.transform).concatenating(fit)
        if let clip { part.clip(to: clip) }
        guard placement.opacity < 1 else {
            part.draw(shapes)
            return
        }
        // A fading part fades as one piece, so its overlapping shapes don't show through.
        part.opacity = placement.opacity
        part.drawLayer { layer in layer.draw(shapes) }
    }

    /// Paints shapes back to front in this context's transform.
    func draw(_ shapes: [FigureDrawing.DrawableShape]) {
        for shape in shapes {
            var each = self
            each.opacity *= shape.opacity
            guard shape.opacity < 1, shape.fill != nil, shape.stroke != nil else {
                each.paint(shape)
                continue
            }
            // As in SVG, fill and stroke fade together, so the stroke doesn't darken the fill under it.
            each.drawLayer { layer in layer.paint(shape) }
        }
    }

    private func paint(_ shape: FigureDrawing.DrawableShape) {
        if let fill = shape.fill { self.fill(shape.path, with: .color(fill)) }
        if let stroke = shape.stroke { self.stroke(shape.path, with: .color(stroke.color), style: stroke.style) }
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

extension Path {
    /// A closed polygon.
    init(_ corners: [CGPoint]) {
        self.init()
        addLines(corners)
        closeSubpath()
    }
}

extension Point {
    init(_ point: CGPoint) {
        self.init(x: point.x, y: point.y)
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
    /// A color of the character's art, such as a swatch to dress it in.
    public init(_ color: RGBAColor) {
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
