/// A 头衔徽章's colours, the approved 软糖厚章 (thick candy badge): flat tones of one colour, with
/// no gradient or glow, stacked so the badge reads as a thick, rounded piece. The face is the
/// colour itself; the side under it, the lit edge at its top left and the shade at its bottom
/// right are the same colour darker or lighter.
public struct BadgeColors: Sendable, Hashable {
    /// The top of the badge, under the glyph: the colour itself.
    public let face: SRGBColor
    /// Its thickness, showing below the face.
    public let side: SRGBColor
    /// The rounded edge catching the light at the top left.
    public let lit: SRGBColor
    /// The rounded edge in shade at the bottom right.
    public let shade: SRGBColor

    /// The colours of a badge in `tone`.
    public init(tone: SRGBColor) {
        face = tone
        side = tone.scaled(by: Self.sideShade)
        lit = tone.mixed(with: Palette.white, amount: Self.litTint)
        shade = tone.scaled(by: Self.edgeShade)
    }

    /// The colours of a badge named by `colour`, an id in the badge catalog, painted in `tone`
    /// (`#RRGGBB`) when the server sent one; else, as builds before tones did, in the colour of
    /// the scene of that id, and the gym's for any other.
    public init(colour: String, tone: String?) {
        let scene = SceneTheme(rawValue: colour) ?? .gym
        self.init(tone: tone.flatMap(SRGBColor.init(hex:)) ?? scene.colors.accent)
    }

    static let sideShade = 0.55
    static let litTint = 0.4
    static let edgeShade = 0.82
}

extension SRGBColor {
    /// The colour with each channel scaled by `factor` (below 1 darkens it), kept in range.
    public func scaled(by factor: Double) -> SRGBColor {
        func scale(_ channel: UInt8) -> UInt8 { UInt8(min(255, max(0, (Double(channel) * factor).rounded()))) }
        return SRGBColor(red: scale(red), green: scale(green), blue: scale(blue))
    }

    /// The colour moved `amount` (0 to 1) of the way to `other`.
    public func mixed(with other: SRGBColor, amount: Double) -> SRGBColor {
        func mix(_ from: UInt8, _ target: UInt8) -> UInt8 {
            UInt8(min(255, max(0, (Double(from) + (Double(target) - Double(from)) * amount).rounded())))
        }
        return SRGBColor(red: mix(red, other.red), green: mix(green, other.green), blue: mix(blue, other.blue))
    }
}
