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
    /// Denominators, placeholders and chevrons: large type and decoration only (2.1:1 on white).
    public static let inkTertiary = SRGBColor(red: 0xAE, green: 0xB2, blue: 0xBC)
    /// Apple's own black, for the Sign in with Apple style button only.
    public static let appleBlack = SRGBColor(red: 0x00, green: 0x00, blue: 0x00)

    // MARK: Pool scene

    public static let poolSignature = SRGBColor(red: 0x07, green: 0x9B, blue: 0xB8)
    public static let poolWash = SRGBColor(red: 0xE2, green: 0xF5, blue: 0xF9)
    /// Pool-colored text. The signature itself is 2.9:1 on the pool wash, too faint for small text.
    public static let poolText = SRGBColor(red: 0x06, green: 0x6E, blue: 0x83)
    /// The ground the squad stands on, a step deeper than the wash.
    public static let poolFloor = SRGBColor(red: 0xCD, green: 0xEB, blue: 0xF1)

    // MARK: Track scene

    public static let trackSignature = SRGBColor(red: 0xE6, green: 0x53, blue: 0x45)
    /// A warm light color: the track scene's own wash, never a neutral.
    public static let trackWash = SRGBColor(red: 0xFC, green: 0xED, blue: 0xEB)
    public static let trackText = SRGBColor(red: 0xB8, green: 0x33, blue: 0x25)
    public static let trackFloor = SRGBColor(red: 0xF8, green: 0xDD, blue: 0xD9)

    // MARK: Gym scene: the one dark scene

    public static let graphite = SRGBColor(red: 0x1F, green: 0x21, blue: 0x28)
    public static let gymWash = SRGBColor(red: 0xEE, green: 0xF0, blue: 0xF2)
    /// Text, icons and progress on graphite. Never a large background.
    public static let volt = SRGBColor(red: 0xC6, green: 0xF4, blue: 0x32)
    /// The check-in kind buttons on the gym's dark floor: graphite with a hint of volt.
    public static let gymKind = SRGBColor(red: 0x2E, green: 0x33, blue: 0x24)

    // MARK: Tennis scene (grass, not blue hard court)

    public static let tennisSignature = SRGBColor(red: 0x4F, green: 0x6B, blue: 0x22)
    public static let tennisWash = SRGBColor(red: 0xEE, green: 0xF2, blue: 0xE4)
    public static let tennisText = SRGBColor(red: 0x41, green: 0x59, blue: 0x1B)
    public static let tennisFloor = SRGBColor(red: 0xDD, green: 0xE6, blue: 0xCC)

    // MARK: Climbing scene (warm rock brick)

    public static let climbingSignature = SRGBColor(red: 0x8E, green: 0x4A, blue: 0x2C)
    /// A warm light color: the climbing scene's own wash, never a neutral.
    public static let climbingWash = SRGBColor(red: 0xF6, green: 0xED, blue: 0xE8)
    public static let climbingText = SRGBColor(red: 0x7A, green: 0x3E, blue: 0x24)
    public static let climbingFloor = SRGBColor(red: 0xEB, green: 0xDD, blue: 0xD5)

    // MARK: Clothes: outfit swatches for the character only, never UI color

    public static let cobalt = SRGBColor(red: 0x2D, green: 0x5B, blue: 0xA0)
    public static let mint = SRGBColor(red: 0x27, green: 0x8C, blue: 0x5E)
    public static let honey = SRGBColor(red: 0xA0, green: 0x76, blue: 0x0E)
    public static let lavender = SRGBColor(red: 0x90, green: 0x62, blue: 0xDE)

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
    /// Dog fur: golden, cream, apricot, chocolate, black, white.
    public static let dogFur = [
        SRGBColor(red: 0xE2, green: 0xB2, blue: 0x6C),
        SRGBColor(red: 0xF1, green: 0xDD, blue: 0xB8),
        SRGBColor(red: 0xD9, green: 0x8B, blue: 0x4A),
        SRGBColor(red: 0x7A, green: 0x4E, blue: 0x36),
        SRGBColor(red: 0x2F, green: 0x2B, blue: 0x34),
        SRGBColor(red: 0xFB, green: 0xFA, blue: 0xF6),
    ]
    /// Rabbit fur: white, cream, brown, gray, dark gray, black.
    public static let rabbitFur = [
        SRGBColor(red: 0xFB, green: 0xFA, blue: 0xF6),
        SRGBColor(red: 0xE9, green: 0xD2, blue: 0xB4),
        SRGBColor(red: 0xB9, green: 0x8A, blue: 0x64),
        SRGBColor(red: 0x9C, green: 0x9A, blue: 0xA3),
        SRGBColor(red: 0x5C, green: 0x58, blue: 0x62),
        SRGBColor(red: 0x3D, green: 0x38, blue: 0x42),
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
    /// Eyes: near-black, dark brown, amber brown, blue, green, gray.
    public static let eyeColors = [
        SRGBColor(red: 0x22, green: 0x25, blue: 0x2E),
        SRGBColor(red: 0x4A, green: 0x33, blue: 0x26),
        SRGBColor(red: 0x8A, green: 0x5A, blue: 0x2B),
        SRGBColor(red: 0x4A, green: 0x6F, blue: 0xA5),
        SRGBColor(red: 0x4F, green: 0x7A, blue: 0x5E),
        SRGBColor(red: 0x6B, green: 0x6F, blue: 0x80),
    ]
}
