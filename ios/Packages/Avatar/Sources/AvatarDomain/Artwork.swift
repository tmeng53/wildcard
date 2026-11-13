/// A color as an SVG file writes it, plus how opaque it is.
public struct RGBAColor: Hashable, Sendable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8
    /// 0 is invisible, 1 is solid.
    public var opacity: Double

    public init(red: UInt8, green: UInt8, blue: UInt8, opacity: Double = 1) {
        (self.red, self.green, self.blue, self.opacity) = (red, green, blue, opacity)
    }
}

/// One step of a vector path, in canvas coordinates.
public enum PathElement: Hashable, Sendable {
    case move(Point)
    case line(Point)
    case quadCurve(end: Point, control: Point)
    case curve(end: Point, control1: Point, control2: Point)
    case close
}

public struct Stroke: Hashable, Sendable {
    public enum Cap: String, Sendable { case butt, round, square }
    public enum Join: String, Sendable { case miter, round, bevel }

    public var color: RGBAColor
    public var width: Double
    public var cap: Cap
    public var join: Join
    /// Dash and gap lengths, repeating, for a stitched line; empty for a solid one.
    public var dash: [Double]

    public init(color: RGBAColor, width: Double, cap: Cap = .butt, join: Join = .miter, dash: [Double] = []) {
        (self.color, self.width, self.cap, self.join, self.dash) = (color, width, cap, join, dash)
    }
}

/// A filled and/or stroked path: one SVG element.
public struct ArtShape: Hashable, Sendable {
    public var path: [PathElement]
    public var fill: RGBAColor?
    public var stroke: Stroke?
    /// The element's own opacity, applied to its fill and stroke together.
    public var opacity: Double

    public init(path: [PathElement], fill: RGBAColor?, stroke: Stroke?, opacity: Double = 1) {
        (self.path, self.fill, self.stroke, self.opacity) = (path, fill, stroke, opacity)
    }
}

/// One art file: its canvas size and shapes, back to front.
public struct Artwork: Hashable, Sendable {
    public var width: Double
    public var height: Double
    public var shapes: [ArtShape]

    public init(width: Double, height: Double, shapes: [ArtShape]) {
        (self.width, self.height, self.shapes) = (width, height, shapes)
    }
}
