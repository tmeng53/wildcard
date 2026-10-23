import Foundation

/// The colors a variant's art lets a look change: its main color and the shades drawn from
/// it, such as outlines, folds and stripes. Read from `<slot>/<variant>/tones.json`. Every
/// other color in the art (shoes, blush, highlights, trim) keeps its own.
public struct Tones: Hashable, Sendable {
    public let base: RGBAColor
    public let shades: [RGBAColor]

    public init(base: RGBAColor, shades: [RGBAColor]) {
        (self.base, self.shades) = (base, shades)
    }

    /// `{"version": 1, "base": "#2D5BA0", "shades": ["#28467E"]}`
    public static func decode(_ data: Data) throws(AvatarError) -> Tones {
        let file: TonesFile = try decodeJSON(data, version: 1, shape: TonesFile.shape)
        guard let base = RGBAColor(hex: file.base) else { throw .malformedJSON(".base: not a #rrggbb color") }
        var shades: [RGBAColor] = []
        for (index, text) in file.shades.enumerated() {
            guard let shade = RGBAColor(hex: text) else {
                throw .malformedJSON(".shades[\(index)]: not a #rrggbb color")
            }
            shades.append(shade)
        }
        return Tones(base: base, shades: shades)
    }

    /// The base and every shade, ignoring opacity.
    var all: [RGBAColor] { [base] + shades }

    /// Whether `color` is one of these tones, ignoring opacity.
    func contains(_ color: RGBAColor) -> Bool {
        all.contains { $0.sameRGB(as: color) }
    }
}

private struct TonesFile: Decodable {
    static let shape = JSONShape.object(["version": .value, "base": .value, "shades": .array(.value)])

    let base: String
    let shades: [String]
}

/// One slot's tones moved to a new main color.
struct Recolor: Sendable {
    let tones: Tones
    let color: RGBAColor

    /// The artwork with every fill and stroke in `tones` moved to `color`.
    func applied(to artwork: Artwork) -> Artwork {
        var recolored = artwork
        recolored.shapes = artwork.shapes.map { shape in
            var shape = shape
            shape.fill = shape.fill.map(moved)
            if let stroke = shape.stroke { shape.stroke?.color = moved(stroke.color) }
            return shape
        }
        return recolored
    }

    private func moved(_ paint: RGBAColor) -> RGBAColor {
        tones.contains(paint) ? paint.recolored(from: tones.base, to: color) : paint
    }
}

extension Artwork {
    /// Every fill and stroke color, back to front.
    var colors: [RGBAColor] {
        shapes.flatMap { [$0.fill, $0.stroke?.color].compactMap { $0 } }
    }
}

extension RGBAColor {
    /// `#rrggbb` or `#rgb`, solid; nil for anything else.
    public init?(hex text: String) {
        var hex = Substring(text)
        guard hex.first == "#" else { return nil }
        hex = hex.dropFirst()
        if hex.count == 3 { hex = Substring(hex.flatMap { [$0, $0] }) }
        guard hex.count == 6, hex.allSatisfy(\.isHexDigit), let value = UInt32(hex, radix: 16) else { return nil }
        self.init(red: UInt8(value >> 16 & 0xFF), green: UInt8(value >> 8 & 0xFF), blue: UInt8(value & 0xFF))
    }

    /// `#RRGGBB` in capitals, whatever the opacity.
    public var hex: String {
        "#"
            + [red, green, blue].map { byte in
                let digits = String(byte, radix: 16, uppercase: true)
                return digits.count == 1 ? "0" + digits : digits
            }.joined()
    }

    /// The same red, green and blue, whatever the opacity.
    func sameRGB(as other: RGBAColor) -> Bool {
        (red, green, blue) == (other.red, other.green, other.blue)
    }

    /// This color moved the way `base` moves to `target`: hue turned by the same amount,
    /// saturation and lightness scaled in the same proportion. So an outline that is a
    /// darker `base` becomes an equally darker `target`, and `base` itself becomes `target`
    /// exactly. Opacity is kept.
    public func recolored(from base: RGBAColor, to target: RGBAColor) -> RGBAColor {
        if sameRGB(as: base) {
            return RGBAColor(red: target.red, green: target.green, blue: target.blue, opacity: opacity)
        }
        let (own, from, goal) = (HSL(self), HSL(base), HSL(target))
        func scaled(_ value: Double, _ reference: Double, _ goal: Double) -> Double {
            // A gray base has no saturation to scale from; take the target's own.
            reference == 0 ? goal : min(max(goal * value / reference, 0), 1)
        }
        let moved = HSL(
            // A gray base has no hue to turn from, so shades take the target's.
            hue: from.saturation == 0 ? goal.hue : goal.hue + own.hue - from.hue,
            saturation: scaled(own.saturation, from.saturation, goal.saturation),
            lightness: scaled(own.lightness, from.lightness, goal.lightness))
        return moved.color(opacity: opacity)
    }
}

/// Hue in degrees, saturation and lightness from 0 to 1.
private struct HSL {
    var hue: Double
    var saturation: Double
    var lightness: Double

    init(hue: Double, saturation: Double, lightness: Double) {
        (self.hue, self.saturation, self.lightness) = (hue, saturation, lightness)
    }

    init(_ color: RGBAColor) {
        let (red, green, blue) = (Double(color.red) / 255, Double(color.green) / 255, Double(color.blue) / 255)
        let high = max(red, green, blue)
        let low = min(red, green, blue)
        let range = high - low
        lightness = (high + low) / 2
        guard range > 0 else {
            (hue, saturation) = (0, 0)
            return
        }
        saturation = range / (1 - abs(2 * lightness - 1))
        let sector: Double
        switch high {
        case red: sector = ((green - blue) / range).truncatingRemainder(dividingBy: 6)
        case green: sector = (blue - red) / range + 2
        default: sector = (red - green) / range + 4
        }
        hue = sector * 60
    }

    func color(opacity: Double) -> RGBAColor {
        let wrapped = hue.truncatingRemainder(dividingBy: 360)
        let turn = wrapped < 0 ? wrapped + 360 : wrapped
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let second = chroma * (1 - abs((turn / 60).truncatingRemainder(dividingBy: 2) - 1))
        let (red, green, blue): (Double, Double, Double)
        switch turn {
        case ..<60: (red, green, blue) = (chroma, second, 0)
        case ..<120: (red, green, blue) = (second, chroma, 0)
        case ..<180: (red, green, blue) = (0, chroma, second)
        case ..<240: (red, green, blue) = (0, second, chroma)
        case ..<300: (red, green, blue) = (second, 0, chroma)
        default: (red, green, blue) = (chroma, 0, second)
        }
        let lift = lightness - chroma / 2
        func byte(_ channel: Double) -> UInt8 { UInt8(min(max(((channel + lift) * 255).rounded(), 0), 255)) }
        return RGBAColor(red: byte(red), green: byte(green), blue: byte(blue), opacity: opacity)
    }
}
