/// The raw colors of a sunny track meet. Screens use `ColorRole`, not these, so a role can
/// change its color in one place.
public enum Palette {
    /// Ink navy: text, icons and the dark broadcast surfaces.
    public static let ink = RGBColor(red: 0x0E, green: 0x1B, blue: 0x3D)
    /// Secondary text. Readable (4.5:1 or more) on `white` and `chalk`.
    public static let inkMuted = RGBColor(red: 0x56, green: 0x62, blue: 0x7F)
    /// Track red: the one brand color, for the track surface and the main action.
    public static let track = RGBColor(red: 0xEE, green: 0x5A, blue: 0x36)
    /// Broadcast blue: sky, lanes and links.
    public static let sky = RGBColor(red: 0x1F, green: 0x6B, blue: 0xFF)
    /// Pale sky for scene backgrounds. Cool, never cream.
    public static let skyWash = RGBColor(red: 0xE6, green: 0xEF, blue: 0xFF)
    /// Medal gold: only for achievement moments (podium, streak milestones).
    public static let medal = RGBColor(red: 0xF6, green: 0xB9, blue: 0x2B)
    /// Field green: a clean-eating day.
    public static let field = RGBColor(red: 0x1D, green: 0xB3, blue: 0x6B)
    public static let white = RGBColor(red: 0xFF, green: 0xFF, blue: 0xFF)
    /// Chalk: a cool off-white for grouped surfaces.
    public static let chalk = RGBColor(red: 0xF3, green: 0xF6, blue: 0xFB)
    /// Lane line: hairlines and dividers.
    public static let laneLine = RGBColor(red: 0xE1, green: 0xE7, blue: 0xF0)
}

/// What a color is for. Each role's pairing rules are tested in `DesignSystemTests`.
public enum ColorRole: String, CaseIterable, Sendable {
    case canvas
    case surface
    case divider
    case textPrimary
    case textSecondary
    /// Text and icons drawn on `brand`, `sky` or `textPrimary` fills.
    case textOnFill
    case brand
    case sky
    case skyWash
    case achievement
    case fresh

    public var color: RGBColor {
        switch self {
        case .canvas: Palette.white
        case .surface: Palette.chalk
        case .divider: Palette.laneLine
        case .textPrimary: Palette.ink
        case .textSecondary: Palette.inkMuted
        case .textOnFill: Palette.white
        case .brand: Palette.track
        case .sky: Palette.sky
        case .skyWash: Palette.skyWash
        case .achievement: Palette.medal
        case .fresh: Palette.field
        }
    }
}
