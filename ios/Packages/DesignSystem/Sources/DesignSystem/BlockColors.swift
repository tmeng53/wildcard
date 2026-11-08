/// The colours of a solid block in one colour with white on it: a post block, a 成绩条, a route's
/// line, a chart. The colour comes as data (a sport category's, Tracy 2026-11-08), so a new one
/// needs no release; the words on it are always white.
public struct BlockColors: Sendable, Hashable {
    /// The block itself.
    public let fill: SRGBColor
    /// Words, numbers and icons on it.
    public let ink: SRGBColor
    /// The same colour darker, for a pattern or a line on the block.
    public let shade: SRGBColor

    public init(tone: SRGBColor) {
        fill = tone
        ink = Palette.white
        shade = tone.scaled(by: BadgeColors.edgeShade)
    }

    /// The colours of `hex` (`#RRGGBB`), or of the gym's steel for anything else.
    public init(hex: String?) {
        self.init(tone: hex.flatMap(SRGBColor.init(hex:)) ?? SceneTheme.gym.colors.accent)
    }

    /// A scene's accent with white on it.
    public init(scene: SceneTheme) {
        self.init(tone: scene.colors.accent)
    }
}
