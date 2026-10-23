/// What sits between the scene and an open check-in: a light blur, not a grey dim, so the
/// squad and the scene stay visible. There are no shadows and no frost: layers differ by their
/// fill (page white, subtle blocks, solid white cards on the scene), and system Liquid Glass is
/// only for the tab bar, header buttons on the scene, the check-in kinds and 动态's emoji bar,
/// emoji grid and who-reacted panel.
public enum Scrim {
    /// Blur radius in points, equivalent to a 3 px CSS blur.
    public static let blurRadius: Double = 3
    /// A barely-there cool tint over the blur.
    public static let tint = SRGBColor(red: 0xE8, green: 0xF6, blue: 0xFA)
    public static let tintOpacity: Double = 0.10
    /// Seconds to fade in and out.
    public static let fadeIn: Double = 0.20
    public static let fadeOut: Double = 0.16
}
