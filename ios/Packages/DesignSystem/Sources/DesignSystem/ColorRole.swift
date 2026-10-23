/// The scene a squad picked. A scene swaps only its accent group (primary actions, selection,
/// the scene's washes and floor, check-in kinds and status rings); neutrals stay fixed.
public enum SceneTheme: String, CaseIterable, Sendable {
    case pool
    case track
    case gym
    case tennis
    case climbing

    public var colors: SceneColors {
        switch self {
        case .pool:
            .light(
                accent: Palette.poolSignature, subtle: Palette.poolWash, text: Palette.poolText,
                floor: Palette.poolFloor)
        case .track:
            .light(
                accent: Palette.trackSignature, subtle: Palette.trackWash, text: Palette.trackText,
                floor: Palette.trackFloor)
        case .gym:
            // Graphite is dark, so what sits on it is volt: the primary button's label, the ring,
            // and the check-in kinds on the gym's dark floor. Volt on a white card is faint, so
            // with Increase Contrast on the ring turns graphite.
            SceneColors(
                accent: Palette.graphite, accentSubtle: Palette.gymWash, onAccent: Palette.volt,
                accentText: Palette.graphite, floor: Palette.graphite, onFloor: Palette.white, ring: Palette.volt,
                ringIncreasedContrast: Palette.graphite, kindFill: Palette.gymKind, kindFillOnFloor: Palette.gymKind,
                kindInk: Palette.volt)
        case .tennis:
            .light(
                accent: Palette.tennisSignature, subtle: Palette.tennisWash, text: Palette.tennisText,
                floor: Palette.tennisFloor)
        case .climbing:
            .light(
                accent: Palette.climbingSignature, subtle: Palette.climbingWash, text: Palette.climbingText,
                floor: Palette.climbingFloor)
        }
    }
}

/// One scene's accent group.
public struct SceneColors: Sendable, Hashable {
    /// The scene's one accent: primary buttons and selection. One accent per screen.
    public let accent: SRGBColor
    /// The light scene wash: tags and the check-in kind buttons on white.
    public let accentSubtle: SRGBColor
    /// Labels and icons drawn on `accent`.
    public let onAccent: SRGBColor
    /// Accent-colored text and icons on white or `accentSubtle`.
    public let accentText: SRGBColor
    /// The ground the squad stands on in the scene.
    public let floor: SRGBColor
    /// Text drawn straight on `floor`.
    public let onFloor: SRGBColor
    /// A status ring once someone checked in: the scene's brightest color.
    public let ring: SRGBColor
    /// The ring on a white card when the person turned on Increase Contrast.
    public let ringIncreasedContrast: SRGBColor
    /// A check-in kind button on white.
    public let kindFill: SRGBColor
    /// A check-in kind button on the scene's floor.
    public let kindFillOnFloor: SRGBColor
    /// The icon on a check-in kind button.
    public let kindInk: SRGBColor

    /// A light scene: white on the accent, the accent as the ring, kinds on the wash or white.
    static func light(accent: SRGBColor, subtle: SRGBColor, text: SRGBColor, floor: SRGBColor) -> SceneColors {
        SceneColors(
            accent: accent, accentSubtle: subtle, onAccent: Palette.white, accentText: text, floor: floor,
            onFloor: Palette.ink, ring: accent, ringIncreasedContrast: accent, kindFill: subtle,
            kindFillOnFloor: Palette.white, kindInk: text)
    }
}

/// The four check-in kinds. They share the scene's colors and differ by icon and word only.
public enum CheckInKind: String, CaseIterable, Sendable {
    /// 练了.
    case trained
    /// 健康餐.
    case healthyMeal
    /// 坦白放纵餐.
    case cheatMeal
    /// 今日请假条.
    case disclaimer
}

/// What a color is for, named like Primer and Polaris: `bg`, `fg` or `border`, then what it is.
/// Screens use these, never `Palette`. Each role's pairing rules are tested in `DesignSystemTests`.
public enum ColorRole: String, CaseIterable, Sendable {
    /// The page: white.
    case bgCanvas
    /// Blocks set into the page, unselected tracks, cards on a white page.
    case bgSubtle
    /// Dividers, hairline borders and unfinished steps.
    case borderDefault
    /// Titles and body text.
    case fgDefault
    /// Secondary text and values.
    case fgMuted
    /// Placeholders, denominators and chevrons: large type and decoration only.
    case fgSubtle
    /// An ink surface on a white page, such as 我's player card.
    case bgInk
    /// Text and numbers on `bgInk`.
    case fgOnInk
    /// Secondary text on `bgInk`.
    case fgOnInkMuted
    /// Dividers on `bgInk`.
    case borderOnInk

    /// The scene's accent: primary buttons and selection, nothing else.
    case bgAccent
    /// The scene's wash: tags.
    case bgAccentSubtle
    /// Labels and icons on `bgAccent`.
    case fgOnAccent
    /// Accent-colored text and icons on white or `bgAccentSubtle`.
    case fgAccent
    /// The scene's floor, under the squad.
    case bgScene
    /// Text straight on `bgScene`.
    case fgOnScene
    /// A status ring once someone checked in, on a white card.
    case ring
    /// A check-in kind button on white.
    case bgKind
    /// A check-in kind button on the scene's floor.
    case bgKindOnScene
    /// The icon on a check-in kind button.
    case fgKind

    /// The color this role takes in a scene, and with Increase Contrast on (only the ring changes).
    public func color(in theme: SceneTheme, contrast: ColorContrast = .standard) -> SRGBColor {
        if self == .ring, contrast == .increased { return theme.colors.ringIncreasedContrast }
        switch source {
        case .fixed(let color): return color
        case .scene(let path): return theme.colors[keyPath: path]
        }
    }

    private enum Source {
        case fixed(SRGBColor)
        case scene(KeyPath<SceneColors, SRGBColor>)
    }

    private var source: Source {
        switch self {
        case .bgCanvas: .fixed(Palette.white)
        case .bgSubtle: .fixed(Palette.mist)
        case .borderDefault: .fixed(Palette.line)
        case .fgDefault: .fixed(Palette.ink)
        case .fgMuted: .fixed(Palette.inkSecondary)
        case .fgSubtle: .fixed(Palette.inkTertiary)
        case .bgInk: .fixed(Palette.ink)
        case .fgOnInk: .fixed(Palette.white)
        case .fgOnInkMuted: .fixed(Palette.inkTertiary)
        case .borderOnInk: .fixed(Palette.inkLine)
        case .bgAccent: .scene(\.accent)
        case .bgAccentSubtle: .scene(\.accentSubtle)
        case .fgOnAccent: .scene(\.onAccent)
        case .fgAccent: .scene(\.accentText)
        case .bgScene: .scene(\.floor)
        case .fgOnScene: .scene(\.onFloor)
        case .ring: .scene(\.ring)
        case .bgKind: .scene(\.kindFill)
        case .bgKindOnScene: .scene(\.kindFillOnFloor)
        case .fgKind: .scene(\.kindInk)
        }
    }
}

/// Whether the person turned on Increase Contrast (Settings, Accessibility, Display & Text Size).
public enum ColorContrast: Sendable {
    case standard
    case increased
}
