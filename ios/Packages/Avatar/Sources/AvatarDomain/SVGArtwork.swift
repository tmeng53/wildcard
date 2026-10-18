import Foundation

#if canImport(FoundationXML)
import FoundationXML
#endif

extension Artwork {
    /// Reads one flat SVG art file: `path`, `circle`, `ellipse` and `rect` elements, grouped
    /// with `g` if you like, colored with hex fills and strokes. Anything else is an error,
    /// so art never looks different on the phone from how it looked in the design tool.
    /// Internal: callers load art through `Figure`, which reports `AvatarError.invalidSVG`.
    init(svg: String) throws(SVGProblem) {
        let reader = SVGReader()
        let parser = XMLParser(data: Data(svg.utf8))
        parser.delegate = reader
        let parsed = parser.parse()
        if let problem = reader.problem { throw problem }
        guard parsed else { throw .notXML(parser.parserError.map { "\($0)" } ?? "unreadable") }
        guard let viewBox = reader.viewBox else { throw .missingViewBox }
        self.init(width: viewBox.width, height: viewBox.height, shapes: reader.shapes)
    }
}

/// Paint attributes a `g` passes down to its children. Opacity isn't one: a group fades
/// as one piece in SVG, which per-shape opacity can't show, so `opacity` is only read on shapes.
private struct Style {
    var fill: RGBAColor? = RGBAColor(red: 0, green: 0, blue: 0)  // SVG's default fill is black
    var fillOpacity = 1.0
    var stroke: RGBAColor?
    var strokeOpacity = 1.0
    var strokeWidth = 1.0
    var cap = Stroke.Cap.butt
    var join = Stroke.Join.miter
}

private final class SVGReader: NSObject, XMLParserDelegate {
    var shapes: [ArtShape] = []
    var viewBox: (width: Double, height: Double)?
    var problem: SVGProblem?
    private var styles = [Style()]
    /// Inside `title`, `desc` or `metadata`, whose content isn't drawn.
    private var ignoredDepth = 0

    private static let ignored: Set<String> = ["title", "desc", "metadata"]
    /// Attributes that don't change how anything looks.
    private static let inert: Set<String> = ["id", "class", "xmlns", "xmlns:xlink", "version"]
    /// Where an element sits; an `svg`'s own width and height are ignored for its `viewBox`.
    private static let geometry: Set<String> = [
        "viewBox", "d", "cx", "cy", "r", "rx", "ry", "x", "y", "width", "height",
    ]

    func parser(
        _ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
        qualifiedName: String?, attributes: [String: String] = [:]
    ) {
        guard problem == nil else { return }
        if ignoredDepth > 0 || Self.ignored.contains(name) {
            ignoredDepth += 1
            return
        }
        do {
            try start(name, attributes)
        } catch {
            problem = error
            parser.abortParsing()
        }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if ignoredDepth > 0 {
            ignoredDepth -= 1
            return
        }
        if name == "svg" || name == "g" { styles.removeLast() }
    }

    private func start(_ name: String, _ given: [String: String]) throws(SVGProblem) {
        var style = styles[styles.count - 1]
        var opacity = 1.0
        var geometry: [String: String] = [:]
        for (key, value) in Self.expandingStyle(given) {
            if key == "opacity" {
                guard name != "svg", name != "g" else { throw .unsupportedAttribute("opacity on \(name)") }
                opacity = try number(value)
            } else if Self.geometry.contains(key) {
                geometry[key] = value
            } else if !Self.inert.contains(key) {
                try paint(key, value, into: &style)
            }
        }
        switch name {
        case "svg":
            viewBox = try viewBox(geometry)
            styles.append(style)
        case "g":
            styles.append(style)
        default:
            add(try shape(name, geometry), style, opacity)
        }
    }

    /// Declarations in a `style` attribute count as attributes of their own.
    private static func expandingStyle(_ given: [String: String]) -> [String: String] {
        var attributes = given
        guard let style = attributes.removeValue(forKey: "style") else { return attributes }
        for declaration in style.split(separator: ";") {
            let pair = declaration.split(separator: ":", maxSplits: 1)
            guard pair.count == 2 else { continue }
            attributes[pair[0].trimmingCharacters(in: .whitespaces)] = pair[1].trimmingCharacters(in: .whitespaces)
        }
        return attributes
    }

    private func paint(_ key: String, _ value: String, into style: inout Style) throws(SVGProblem) {
        switch key {
        case "fill": style.fill = try color(value)
        case "fill-opacity": style.fillOpacity = try number(value)
        case "stroke": style.stroke = try color(value)
        case "stroke-opacity": style.strokeOpacity = try number(value)
        case "stroke-width": style.strokeWidth = try number(value)
        case "stroke-linecap":
            guard let cap = Stroke.Cap(rawValue: value) else { throw .unsupportedAttribute("\(key)=\(value)") }
            style.cap = cap
        case "stroke-linejoin":
            guard let join = Stroke.Join(rawValue: value) else { throw .unsupportedAttribute("\(key)=\(value)") }
            style.join = join
        default: throw .unsupportedAttribute(key)
        }
    }

    /// The canvas size; the origin must be 0 0, as design tools export an artboard.
    private func viewBox(_ geometry: [String: String]) throws(SVGProblem) -> (width: Double, height: Double) {
        guard let box = geometry["viewBox"] else { throw .missingViewBox }
        var scanner = NumberScanner(Array(box.unicodeScalars))
        let numbers = try (0..<4).map { _ throws(SVGProblem) in try scanner.number() }
        guard numbers[0] == 0, numbers[1] == 0 else { throw .unsupportedAttribute("viewBox origin") }
        return (numbers[2], numbers[3])
    }

    private func shape(_ name: String, _ geometry: [String: String]) throws(SVGProblem) -> [PathElement] {
        switch name {
        case "path":
            return try PathData.parse(require("d", of: name, in: geometry))
        case "circle":
            let radius = try number(require("r", of: name, in: geometry))
            return try ellipse(geometry, radiusX: radius, radiusY: radius)
        case "ellipse":
            let radiusX = try number(require("rx", of: name, in: geometry))
            let radiusY = try number(require("ry", of: name, in: geometry))
            return try ellipse(geometry, radiusX: radiusX, radiusY: radiusY)
        case "rect":
            return try rect(geometry)
        default:
            throw .unsupportedElement(name)
        }
    }

    private func add(_ path: [PathElement], _ style: Style, _ opacity: Double) {
        let fill = style.fill.map { RGBAColor(red: $0.red, green: $0.green, blue: $0.blue, opacity: style.fillOpacity) }
        let stroke = style.stroke.map {
            Stroke(
                color: RGBAColor(red: $0.red, green: $0.green, blue: $0.blue, opacity: style.strokeOpacity),
                width: style.strokeWidth, cap: style.cap, join: style.join)
        }
        shapes.append(ArtShape(path: path, fill: fill, stroke: stroke, opacity: opacity))
    }

    private func require(_ key: String, of element: String, in geometry: [String: String]) throws(SVGProblem)
        -> String
    {
        guard let value = geometry[key] else { throw .missingAttribute(element: element, attribute: key) }
        return value
    }

    private func number(_ text: String) throws(SVGProblem) -> Double {
        var scanner = NumberScanner(Array(text.unicodeScalars))
        let value = try scanner.number()
        scanner.skipSeparators()
        guard scanner.isAtEnd else { throw .invalidNumber(text) }
        return value
    }

    private func optionalNumber(_ key: String, in geometry: [String: String]) throws(SVGProblem) -> Double {
        try geometry[key].map { text throws(SVGProblem) in try number(text) } ?? 0
    }

    /// `none`, `#rgb` or `#rrggbb`.
    private func color(_ text: String) throws(SVGProblem) -> RGBAColor? {
        if text == "none" { return nil }
        var hex = Substring(text)
        guard hex.first == "#" else { throw .invalidColor(text) }
        hex = hex.dropFirst()
        if hex.count == 3 { hex = Substring(hex.flatMap { [$0, $0] }) }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { throw .invalidColor(text) }
        return RGBAColor(red: UInt8(value >> 16 & 0xFF), green: UInt8(value >> 8 & 0xFF), blue: UInt8(value & 0xFF))
    }

    /// Four cubic quarter arcs, the usual Bézier circle.
    private func ellipse(_ geometry: [String: String], radiusX: Double, radiusY: Double) throws(SVGProblem)
        -> [PathElement]
    {
        let centerX = try optionalNumber("cx", in: geometry)
        let centerY = try optionalNumber("cy", in: geometry)
        let kappa = Self.kappa
        func point(_ unitX: Double, _ unitY: Double) -> Point {
            Point(x: centerX + unitX * radiusX, y: centerY + unitY * radiusY)
        }
        return [
            .move(point(1, 0)),
            .curve(end: point(0, 1), control1: point(1, kappa), control2: point(kappa, 1)),
            .curve(end: point(-1, 0), control1: point(-kappa, 1), control2: point(-1, kappa)),
            .curve(end: point(0, -1), control1: point(-1, -kappa), control2: point(-kappa, -1)),
            .curve(end: point(1, 0), control1: point(kappa, -1), control2: point(1, -kappa)),
            .close,
        ]
    }

    /// How far along a quarter arc's tangents its Bézier control points sit.
    private static let kappa = 0.552_284_749_8

    private func rect(_ geometry: [String: String]) throws(SVGProblem) -> [PathElement] {
        let left = try optionalNumber("x", in: geometry)
        let top = try optionalNumber("y", in: geometry)
        let width = try number(require("width", of: "rect", in: geometry))
        let height = try number(require("height", of: "rect", in: geometry))
        let (right, bottom) = (left + width, top + height)
        // A missing rx or ry takes the other's value, then neither passes half the side.
        let givenX = try geometry["rx"].map { text throws(SVGProblem) in try number(text) }
        let givenY = try geometry["ry"].map { text throws(SVGProblem) in try number(text) }
        let radiusX = min(givenX ?? givenY ?? 0, width / 2)
        let radiusY = min(givenY ?? givenX ?? 0, height / 2)
        func point(_ horizontal: Double, _ vertical: Double) -> Point { Point(x: horizontal, y: vertical) }
        guard radiusX > 0, radiusY > 0 else {
            return [
                .move(point(left, top)), .line(point(right, top)), .line(point(right, bottom)),
                .line(point(left, bottom)), .close,
            ]
        }
        // Control points sit this far in from each corner.
        let insetX = radiusX * (1 - Self.kappa)
        let insetY = radiusY * (1 - Self.kappa)
        return [
            .move(point(left + radiusX, top)),
            .line(point(right - radiusX, top)),
            .curve(
                end: point(right, top + radiusY), control1: point(right - insetX, top),
                control2: point(right, top + insetY)),
            .line(point(right, bottom - radiusY)),
            .curve(
                end: point(right - radiusX, bottom), control1: point(right, bottom - insetY),
                control2: point(right - insetX, bottom)),
            .line(point(left + radiusX, bottom)),
            .curve(
                end: point(left, bottom - radiusY), control1: point(left + insetX, bottom),
                control2: point(left, bottom - insetY)),
            .line(point(left, top + radiusY)),
            .curve(
                end: point(left + radiusX, top), control1: point(left, top + insetY),
                control2: point(left + insetX, top)
            ),
            .close,
        ]
    }
}
