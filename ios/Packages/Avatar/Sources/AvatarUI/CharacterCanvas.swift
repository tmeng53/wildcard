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
    struct Shoulder {
        let parent: Int
        let cloth: Path
        let reach: Path
        let edges: [Edge]
    }

    /// One art layer's cloth as one shape, outlined in the layer's outline just before the
    /// layer's first shape (`before`, an index into the part's shapes), so the layer's own
    /// shapes cover the line's inner half where they cover it at all.
    struct Edge {
        let before: Int
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
                guard cloth.cgPath.intersects(reach.cgPath), let outline = art.outline?.stroke else { continue }
                edges.append(
                    Edge(
                        before: first, cloth: cloth.elements, color: Color(outline.color),
                        style: StrokeStyle(lineWidth: outline.width, lineCap: .round, lineJoin: .round)))
            }
            return Shoulder(
                parent: parent, cloth: Self.cloth(figure.parts[parent].art.flatMap(\.shapes)), reach: reach,
                edges: edges)
        }
    }

    /// The filled shapes as one, each by its own fill rule, so overlapping shapes leave no hole.
    static func cloth(_ shapes: [ArtShape]) -> Path {
        shapes.filter { $0.fill != nil }.reduce(Path()) { cloth, shape in cloth.union(Path(shape.path)) }
    }

    /// Where the part's edge is outlined in `placements`, in the part's own coordinates: off its
    /// body's cloth, within its shoulder's reach. Nil when the part has no shoulder.
    func offBody(_ part: Int, _ placements: [Placement]) -> Path? {
        guard let shoulder = shoulders[part] else { return nil }
        let own = CGAffineTransform(placements[part].transform)
        let parent = CGAffineTransform(placements[shoulder.parent].transform)
        let cloth = shoulder.cloth.applying(parent.concatenating(own.inverted()))
        return shoulder.reach.subtracting(cloth)
    }

    /// A shoulder's edges as `placement` draws them: bent with the arm.
    func edges(_ part: Int, _ placement: Placement) -> [DrawnEdge] {
        (shoulders[part]?.edges ?? []).map { edge in
            DrawnEdge(
                before: edge.before, path: Path(placement.bend.map { $0.apply(to: edge.cloth) } ?? edge.cloth),
                color: edge.color, style: edge.style)
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
            for (index, placement) in zip(drawing.parts.indices, placements)
            where placement.opacity > 0 && !drawing.parts[index].isEmpty {
                let shapes = drawing.shapes(index, placement)
                let edges = drawing.offBody(index, placements).map { area in
                    (area: area, edges: drawing.edges(index, placement))
                }
                var part = context
                part.transform = CGAffineTransform(placement.transform).concatenating(fit)
                guard placement.opacity < 1 else {
                    part.draw(shapes, edges: edges)
                    continue
                }
                // A fading part fades as one piece, so its overlapping shapes don't show through.
                part.opacity = placement.opacity
                part.drawLayer { layer in layer.draw(shapes, edges: edges) }
            }
        }
    }
}

extension GraphicsContext {
    /// Paints shapes back to front in this context's transform, each of `edges` outlined within
    /// `area` (in the same coordinates) before the shape it comes before.
    func draw(
        _ shapes: [FigureDrawing.DrawableShape], edges: (area: Path, edges: [FigureDrawing.DrawnEdge])? = nil
    ) {
        var offBody = self
        if let edges { offBody.clip(to: edges.area) }
        for (index, shape) in shapes.enumerated() {
            for edge in edges?.edges ?? [] where edge.before == index {
                offBody.stroke(edge.path, with: .color(edge.color), style: edge.style)
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
