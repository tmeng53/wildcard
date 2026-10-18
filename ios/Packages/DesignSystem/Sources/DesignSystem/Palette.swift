/// The raw colors. Screens use `ColorRole`, not these, so a role can change its color in one place.
public enum Palette {
    // MARK: Neutrals, the same in every scene

    public static let white = SRGBColor(red: 0xFF, green: 0xFF, blue: 0xFF)
    /// Grouped backgrounds and unselected blocks.
    public static let mist = SRGBColor(red: 0xF3, green: 0xF5, blue: 0xF8)
    /// Dividers, progress tracks and the base edge of raised buttons.
    public static let line = SRGBColor(red: 0xE8, green: 0xEB, blue: 0xF0)
    /// Titles and body text.
    public static let ink = SRGBColor(red: 0x22, green: 0x25, blue: 0x2E)
    /// Secondary text. Readable (4.5:1 or more) on `white` and `mist`.
    public static let inkSecondary = SRGBColor(red: 0x6B, green: 0x70, blue: 0x80)
    /// Denominators and scale marks: large type and decoration only (2.1:1 on white).
    public static let inkTertiary = SRGBColor(red: 0xAE, green: 0xB2, blue: 0xBC)

    // MARK: Pool scene

    public static let poolSignature = SRGBColor(red: 0x07, green: 0x9B, blue: 0xB8)
    public static let poolShade = SRGBColor(red: 0x06, green: 0x7C, blue: 0x93)
    public static let poolWash = SRGBColor(red: 0xE2, green: 0xF5, blue: 0xF9)
    /// Pool-colored text. The signature itself is 2.9:1 on the pool wash, too faint for small text.
    public static let poolText = SRGBColor(red: 0x06, green: 0x6E, blue: 0x83)

    // MARK: Track scene

    public static let trackSignature = SRGBColor(red: 0xE6, green: 0x53, blue: 0x45)
    public static let trackShade = SRGBColor(red: 0xC2, green: 0x3B, blue: 0x2E)
    /// A warm light color: the track scene's own wash, never a neutral.
    public static let trackWash = SRGBColor(red: 0xFC, green: 0xED, blue: 0xEB)
    public static let trackText = SRGBColor(red: 0xB8, green: 0x33, blue: 0x25)

    // MARK: Gym scene

    public static let graphite = SRGBColor(red: 0x1F, green: 0x21, blue: 0x28)
    public static let black = SRGBColor(red: 0x00, green: 0x00, blue: 0x00)
    public static let gymWash = SRGBColor(red: 0xEE, green: 0xF0, blue: 0xF2)
    /// Text, icons and progress on graphite. Never a large background.
    public static let volt = SRGBColor(red: 0xC6, green: 0xF4, blue: 0x32)

    // MARK: Tennis scene (grass, not blue hard court, which would sit next to 练了 cobalt)

    public static let tennisSignature = SRGBColor(red: 0x4F, green: 0x6B, blue: 0x22)
    public static let tennisShade = SRGBColor(red: 0x3B, green: 0x51, blue: 0x19)
    public static let tennisWash = SRGBColor(red: 0xEE, green: 0xF2, blue: 0xE4)
    public static let tennisText = SRGBColor(red: 0x41, green: 0x59, blue: 0x1B)

    // MARK: Climbing scene (warm rock brick, kept apart from the honey 坦白放纵餐)

    public static let climbingSignature = SRGBColor(red: 0x8E, green: 0x4A, blue: 0x2C)
    public static let climbingShade = SRGBColor(red: 0x6F, green: 0x38, blue: 0x20)
    /// A warm light color: the climbing scene's own wash, never a neutral.
    public static let climbingWash = SRGBColor(red: 0xF6, green: 0xED, blue: 0xE8)
    public static let climbingText = SRGBColor(red: 0x7A, green: 0x3E, blue: 0x24)

    // MARK: Meaning accents, fixed in every scene. Icons and dots use the same color.

    /// 练了.
    public static let cobalt = SRGBColor(red: 0x2D, green: 0x5B, blue: 0xA0)
    public static let cobaltWash = SRGBColor(red: 0xEA, green: 0xF0, blue: 0xF8)
    public static let cobaltText = SRGBColor(red: 0x22, green: 0x47, blue: 0x80)
    /// 健康餐.
    public static let mint = SRGBColor(red: 0x27, green: 0x8C, blue: 0x5E)
    public static let mintWash = SRGBColor(red: 0xE5, green: 0xF3, blue: 0xEB)
    public static let mintText = SRGBColor(red: 0x1B, green: 0x65, blue: 0x45)
    /// 坦白放纵餐.
    public static let honey = SRGBColor(red: 0xA0, green: 0x76, blue: 0x0E)
    public static let honeyWash = SRGBColor(red: 0xFB, green: 0xF1, blue: 0xDC)
    public static let honeyText = SRGBColor(red: 0x6E, green: 0x4F, blue: 0x07)
    /// 今日免责声明.
    public static let lavender = SRGBColor(red: 0x90, green: 0x62, blue: 0xDE)
    public static let lavenderWash = SRGBColor(red: 0xF3, green: 0xEE, blue: 0xFC)
    public static let lavenderText = SRGBColor(red: 0x5B, green: 0x3A, blue: 0xA6)
    // MARK: Character tones: the avatar's skin, fur and hair swatches. Never UI color.
    /// Skin, light to deep.
    public static let skinTones = [
        SRGBColor(red: 0xF9, green: 0xDC, blue: 0xC4),
        SRGBColor(red: 0xF5, green: 0xCD, blue: 0xAE),
        SRGBColor(red: 0xE8, green: 0xB4, blue: 0x8F),
        SRGBColor(red: 0xD9, green: 0xA2, blue: 0x7A),
        SRGBColor(red: 0xB9, green: 0x7F, blue: 0x57),
        SRGBColor(red: 0x8D, green: 0x5A, blue: 0x3B),
        SRGBColor(red: 0x5E, green: 0x3B, blue: 0x27),
    ]
    /// Cat fur: orange tabby, cream, gray, black, white, brown tabby.
    public static let catFur = [
        SRGBColor(red: 0xF2, green: 0xA6, blue: 0x5A),
        SRGBColor(red: 0xF6, green: 0xE6, blue: 0xCC),
        SRGBColor(red: 0xA3, green: 0xA7, blue: 0xB0),
        SRGBColor(red: 0x4A, green: 0x46, blue: 0x50),
        SRGBColor(red: 0xFB, green: 0xFA, blue: 0xF6),
        SRGBColor(red: 0xC9, green: 0x87, blue: 0x4F),
    ]
    /// Bear fur: brown, dark brown, honey, polar white, black, grizzly.
    public static let bearFur = [
        SRGBColor(red: 0xB9, green: 0x85, blue: 0x63),
        SRGBColor(red: 0x7E, green: 0x52, blue: 0x36),
        SRGBColor(red: 0xD9, green: 0xB0, blue: 0x7E),
        SRGBColor(red: 0xF2, green: 0xEF, blue: 0xE8),
        SRGBColor(red: 0x3F, green: 0x39, blue: 0x3B),
        SRGBColor(red: 0xA8, green: 0x92, blue: 0x7E),
    ]
    /// Hair: black, dark brown, brown, light brown, blonde, auburn, silver.
    public static let hairColors = [
        SRGBColor(red: 0x2A, green: 0x23, blue: 0x33),
        SRGBColor(red: 0x4A, green: 0x2F, blue: 0x25),
        SRGBColor(red: 0x6B, green: 0x43, blue: 0x30),
        SRGBColor(red: 0xB0, green: 0x7B, blue: 0x4A),
        SRGBColor(red: 0xE2, green: 0xBF, blue: 0x74),
        SRGBColor(red: 0xA2, green: 0x45, blue: 0x2F),
        SRGBColor(red: 0xC4, green: 0xC2, blue: 0xCA),
    ]
}
