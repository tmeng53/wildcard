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
    /// For an arm in front of the body it hangs from (`Figure.Part.shoulder`): where the arm
    /// leaves the body near its pivot, its own edge is outlined, so the two read as one outline
    /// wherever the arm turns.
    let shoulders: [Shoulder?]

    /// The body the arm hangs from, its cloth as one shape in its own coordinates, the circle
    /// around the arm's pivot where the arm's edge is outlined off the body, and that edge.
    /// `top` is the reach's half above the pivot, where a sleeve's outline starts: there the
    /// outline stops at the body, so a raised arm leaves no end of it on the chest.
    struct Shoulder {
        let parent: Int
        let cloth: Path
        let reach: Path
        let top: Path
        let edges: [Edge]
    }

    /// One art layer's cloth as one shape, outlined in the layer's outline just before the
    /// layer's first shape (`before`, an index into the part's shapes), so the layer's own
    /// shapes cover the line's inner half where they cover it at all.
    struct Edge {
        let before: Int
        /// The layer's outline, an index into the part's shapes.
        let outline: Int?
        /// As elements, so it bends with the arm's art.
        let cloth: [PathElement]
        let color: Color
        let style: StrokeStyle
    }

    /// A shoulder's edge as a frame draws it, bent with the arm.
    struct DrawnEdge {
        let before: Int
        let path: Path
        let color: Color
        let style: StrokeStyle
    }

    /// A shoulder in one frame, in the arm's own coordinates: where its edges are outlined (off
    /// the body, within reach), where its sleeves' outlines stop (on the body, in the reach's
    /// top) and which of the arm's shapes are those outlines.
    struct ShoulderFrame {
        let offBody: Path
        let overBody: Path
        let edges: [DrawnEdge]
        let outlines: Set<Int>
    }

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
        shoulders = figure.parts.map { part in
            guard let radius = part.shoulder, let parent = part.parent else { return nil }
            let reach = Path(
                ellipseIn: CGRect(
                    x: part.pivot.x - radius, y: part.pivot.y - radius, width: radius * 2, height: radius * 2))
            var (edges, first) = ([Edge](), 0)
            for art in part.art {
                defer { first += art.shapes.count }
                // Only cloth that reaches the shoulder: a sleeve, not a bare arm's hand.
                let cloth = Self.cloth(art.shapes)
                guard cloth.cgPath.intersects(reach.cgPath), let outline = art.outline, let line = outline.stroke
                else { continue }
                edges.append(
                    Edge(
                        before: first, outline: art.shapes.firstIndex(of: outline).map { first + $0 },
                        cloth: cloth.elements, color: Color(line.color),
                        style: StrokeStyle(lineWidth: line.width, lineCap: .round, lineJoin: .round)))
            }
            let top = reach.intersection(
                Path(CGRect(x: part.pivot.x - radius, y: part.pivot.y - radius, width: radius * 2, height: radius)))
            return Shoulder(
                parent: parent, cloth: Self.cloth(figure.parts[parent].art.flatMap(\.shapes)), reach: reach,
                top: top, edges: edges)
        }
    }

    /// The filled shapes as one, each by its own fill rule, so overlapping shapes leave no hole.
    static func cloth(_ shapes: [ArtShape]) -> Path {
        shapes.filter { $0.fill != nil }.reduce(Path()) { cloth, shape in cloth.union(Path(shape.path)) }
    }

    /// The part's shoulder as `placements` draw it, its edges bent with the arm. Nil when the
    /// part has no shoulder.
    func shoulder(_ part: Int, _ placements: [Placement]) -> ShoulderFrame? {
        guard let shoulder = shoulders[part] else { return nil }
        let own = CGAffineTransform(placements[part].transform)
        let parent = CGAffineTransform(placements[shoulder.parent].transform)
        let cloth = shoulder.cloth.applying(parent.concatenating(own.inverted()))
        let bend = placements[part].bend
        return ShoulderFrame(
            offBody: shoulder.reach.subtracting(cloth), overBody: shoulder.top.intersection(cloth),
            edges: shoulder.edges.map { edge in
                DrawnEdge(
                    before: edge.before, path: Path(bend.map { $0.apply(to: edge.cloth) } ?? edge.cloth),
                    color: edge.color, style: edge.style)
            },
            outlines: Set(shoulder.edges.compactMap(\.outline)))
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
            for (index, placement) in zip(drawing.parts.indices, placements)
            where placement.opacity > 0 && !drawing.parts[index].isEmpty {
                let shapes = drawing.shapes(index, placement)
                let shoulder = drawing.shoulder(index, placements)
                var part = context
                part.transform = CGAffineTransform(placement.transform).concatenating(fit)
                guard placement.opacity < 1 else {
                    part.draw(shapes, shoulder: shoulder)
                    continue
                }
                // A fading part fades as one piece, so its overlapping shapes don't show through.
                part.opacity = placement.opacity
                part.drawLayer { layer in layer.draw(shapes, shoulder: shoulder) }
            }
        }
    }
}

extension GraphicsContext {
    /// Paints shapes back to front in this context's transform. With a shoulder (in the same
    /// coordinates), each of its edges is outlined off the body before the shape it comes
    /// before, and each sleeve's outline stops where it lies on the body at the shoulder's top.
    func draw(_ shapes: [FigureDrawing.DrawableShape], shoulder: FigureDrawing.ShoulderFrame? = nil) {
        var offBody = self
        if let shoulder { offBody.clip(to: shoulder.offBody) }
        for (index, drawn) in shapes.enumerated() {
            for edge in shoulder?.edges ?? [] where edge.before == index {
                offBody.stroke(edge.path, with: .color(edge.color), style: edge.style)
            }
            var shape = drawn
            if let shoulder, shoulder.outlines.contains(index), drawn.fill == nil, !shoulder.overBody.isEmpty {
                // Its centreline is cut, not its paint, so the line ends round where it stops.
                shape = FigureDrawing.DrawableShape(
                    path: Path(drawn.path.cgPath.lineSubtracting(shoulder.overBody.cgPath)), fill: nil,
                    stroke: drawn.stroke, opacity: drawn.opacity)
            }
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
    /// The path as the art's elements, to bend it as the art bends.
    var elements: [PathElement] {
        var elements: [PathElement] = []
        forEach { element in
            switch element {
            case .move(let point): elements.append(.move(Point(point)))
            case .line(let end): elements.append(.line(Point(end)))
            case .quadCurve(let end, let control): elements.append(.quadCurve(end: Point(end), control: Point(control)))
            case .curve(let end, let control1, let control2):
                elements.append(.curve(end: Point(end), control1: Point(control1), control2: Point(control2)))
            case .closeSubpath: elements.append(.close)
            }
        }
        return elements
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
