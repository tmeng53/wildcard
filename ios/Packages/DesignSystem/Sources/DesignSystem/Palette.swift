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
    public static let poolText = SRGBColor(red: 0x06, green: 0x77, blue: 0x8D)

    // MARK: Track scene

    public static let trackSignature = SRGBColor(red: 0xF0, green: 0x40, blue: 0x2F)
    public static let trackShade = SRGBColor(red: 0xC7, green: 0x2E, blue: 0x20)
    /// The one warm light color: the track scene's own wash, never a neutral.
    public static let trackWash = SRGBColor(red: 0xFD, green: 0xED, blue: 0xEA)

    // MARK: Gym scene

    public static let graphite = SRGBColor(red: 0x1F, green: 0x21, blue: 0x28)
    public static let black = SRGBColor(red: 0x00, green: 0x00, blue: 0x00)
    public static let gymWash = SRGBColor(red: 0xEE, green: 0xF0, blue: 0xF2)
    /// Text, icons and progress on graphite. Never a large background.
    public static let volt = SRGBColor(red: 0xC6, green: 0xF4, blue: 0x32)

    // MARK: Tennis and climbing scenes (placeholders until their colors are chosen)

    public static let tennisSignature = SRGBColor(red: 0x2E, green: 0x8B, blue: 0x57)
    public static let tennisShade = SRGBColor(red: 0x22, green: 0x6B, blue: 0x43)
    public static let tennisWash = SRGBColor(red: 0xE5, green: 0xF3, blue: 0xEB)
    public static let climbingSignature = SRGBColor(red: 0xC2, green: 0x62, blue: 0x2D)
    public static let climbingShade = SRGBColor(red: 0x9A, green: 0x4A, blue: 0x1F)
    public static let climbingWash = SRGBColor(red: 0xF1, green: 0xF2, blue: 0xF5)

    // MARK: Meaning accents (placeholders until the retuned values land)

    /// 健康餐.
    public static let mint = SRGBColor(red: 0x2B, green: 0xD4, blue: 0x7D)
    public static let mintInk = SRGBColor(red: 0x14, green: 0x9E, blue: 0x58)
    public static let mintWash = SRGBColor(red: 0xE4, green: 0xF9, blue: 0xEE)
    public static let mintText = SRGBColor(red: 0x0B, green: 0x5E, blue: 0x36)
    /// 坦白放纵餐.
    public static let amber = SRGBColor(red: 0xFF, green: 0xB0, blue: 0x20)
    public static let amberInk = SRGBColor(red: 0xB5, green: 0x7A, blue: 0x00)
    public static let amberWash = SRGBColor(red: 0xFF, green: 0xF4, blue: 0xDD)
    public static let amberText = SRGBColor(red: 0x7A, green: 0x4A, blue: 0x00)
    /// 今日免责声明.
    public static let lavender = SRGBColor(red: 0xA9, green: 0x8B, blue: 0xFF)
    public static let lavenderInk = SRGBColor(red: 0x74, green: 0x57, blue: 0xE8)
    public static let lavenderWash = SRGBColor(red: 0xF2, green: 0xED, blue: 0xFF)
    public static let lavenderText = SRGBColor(red: 0x4B, green: 0x2F, blue: 0xA6)
}
