/// A 头衔徽章's two colours, from the scene whose colour it takes: the enamel is the scene's
/// signature, and the rim around it the same colour a quarter darker, as on an enamel pin.
public struct BadgeColors: Sendable, Hashable {
    public let enamel: SRGBColor
    public let rim: SRGBColor

    /// The colours of a badge in `scene`'s colour.
    public init(scene: SceneTheme) {
        enamel = scene.colors.accent
        rim = enamel.scaled(by: Self.rimShade)
    }

    /// How much of the enamel's light the rim keeps.
    static let rimShade = 0.78
}

extension SRGBColor {
    /// The colour with each channel scaled by `factor` (below 1 darkens it), kept in range.
    public func scaled(by factor: Double) -> SRGBColor {
        func scale(_ channel: UInt8) -> UInt8 { UInt8(min(255, max(0, (Double(channel) * factor).rounded()))) }
        return SRGBColor(red: scale(red), green: scale(green), blue: scale(blue))
    }
}
