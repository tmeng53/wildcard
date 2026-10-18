/// Frosted material for what floats over the scene: the squad banner and the check-in
/// capsules, never content. Plain frost: no rim highlight, no glow, no specular streak.
/// The tab bar is Liquid Glass (`glassEffect`), not frost. Primary actions are solid signature
/// fills, not glass.
public enum Frost {
    /// White over the frost for the squad banner.
    public static let bannerFill: Double = 0.62
    /// White over the frost for the disclaimer draft card.
    public static let cardFill: Double = 0.76
    /// White over the frost for an open check-in capsule.
    public static let capsuleFill: Double = 0.50
}

/// What sits between the scene and an open check-in: a light blur, not a grey dim, so the
/// squad and the scene stay visible.
public enum Scrim {
    /// Blur radius in points, equivalent to a 3 px CSS blur.
    public static let blurRadius: Double = 3
    /// A barely-there cool tint over the blur.
    public static let tint = SRGBColor(red: 0xE8, green: 0xF6, blue: 0xFA)
    public static let tintOpacity: Double = 0.10
    /// Seconds to fade in and out.
    public static let fadeIn: Double = 0.20
    public static let fadeOut: Double = 0.18
}

/// How strongly the signature tints something that isn't a solid fill.
public enum Tint {
    /// The pill behind a selected tab or segment.
    public static let selected: Double = 0.14
}
