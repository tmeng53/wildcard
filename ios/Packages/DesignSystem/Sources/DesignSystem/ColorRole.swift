import Synchronization

/// The scene a squad picked. A scene swaps only its accent group (primary actions, selection,
/// the scene's washes and floor, check-in kinds and status rings); neutrals stay fixed.
///
/// Its id is the API's, and is open: a scene added through the admin tools (`put_scene`) after
/// this build shipped takes its names and colours from the catalog (`list(_:)`), its pictures
/// from the art an admin put (`scenes/<id>-day@3x.png`), and everything this build draws in code
/// for a scene (stations, props, patterns) from the gym, its `base`.
public struct SceneTheme: RawRepresentable, Hashable, Sendable, CaseIterable {
    /// The scenes this build was made with, each drawn in its own way.
    public enum Base: String, CaseIterable, Sendable {
        case pool, track, gym, tennis, climbing
        /// The winter 雪场, open only part of the year (冬季限定).
        case ski
    }

    public let rawValue: String

    /// Nil for a string that can't be a scene id (the API's: camelCase, up to 40 characters).
    public init?(rawValue: String) {
        guard rawValue.wholeMatch(of: /[a-z][A-Za-z0-9]{0,39}/) != nil else { return nil }
        self.rawValue = rawValue
    }

    public init(_ base: Base) {
        rawValue = base.rawValue
    }

    public static let pool = SceneTheme(.pool)
    public static let track = SceneTheme(.track)
    public static let gym = SceneTheme(.gym)
    public static let tennis = SceneTheme(.tennis)
    public static let climbing = SceneTheme(.climbing)
    public static let ski = SceneTheme(.ski)

    /// The scenes this build was made with; the picker offers what the API sends.
    public static var allCases: [SceneTheme] { Base.allCases.map(SceneTheme.init) }

    /// The scene this build draws it as: itself, or the gym for one added since.
    public var base: Base { Base(rawValue: rawValue) ?? .gym }

    public var colors: SceneColors {
        if Base(rawValue: rawValue) == nil, let listed = Self.listing(self) { return listed.colors }
        return base.colors
    }

    /// What the catalog says of a scene this build wasn't made with.
    public struct Listing: Hashable, Sendable {
        public let colors: SceneColors
        /// Its name in Simplified Chinese, English and Traditional Chinese.
        public let simplifiedChinese: String
        public let english: String
        public let traditionalChinese: String

        public init(colors: SceneColors, simplifiedChinese: String, english: String, traditionalChinese: String) {
            self.colors = colors
            (self.simplifiedChinese, self.english, self.traditionalChinese) = (
                simplifiedChinese, english, traditionalChinese
            )
        }
    }

    /// Takes the catalog's scenes (the app does at launch and whenever it reads the API's). Only
    /// a scene this build wasn't made with uses its listing; the rest keep the design's tokens.
    public static func list(_ scenes: [SceneTheme: Listing]) {
        listed.withLock { $0 = scenes }
    }

    /// The catalog's listing of `scene`, if it has one.
    public static func listing(_ scene: SceneTheme) -> Listing? {
        listed.withLock { $0[scene] }
    }

    private static let listed = Mutex<[SceneTheme: Listing]>([:])
}

extension SceneTheme.Base {
    var colors: SceneColors {
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
            .light(
                accent: Palette.gymSignature, subtle: Palette.gymWash, text: Palette.gymText,
                floor: Palette.gymFloor)
        case .tennis:
            .light(
                accent: Palette.tennisSignature, subtle: Palette.tennisWash, text: Palette.tennisText,
                floor: Palette.tennisFloor)
        case .climbing:
            .light(
                accent: Palette.climbingSignature, subtle: Palette.climbingWash, text: Palette.climbingText,
                floor: Palette.climbingFloor)
        case .ski:
            .light(
                accent: Palette.skiSignature, subtle: Palette.skiWash, text: Palette.skiText,
                floor: Palette.skiFloor, onAccent: Palette.skiOnSignature)
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
    /// A check-in kind button on white.
    public let kindFill: SRGBColor
    /// A check-in kind button on the scene's floor.
    public let kindFillOnFloor: SRGBColor
    /// The icon on a check-in kind button.
    public let kindInk: SRGBColor

    /// A light scene: white on the accent, the accent as the ring, kinds on the wash or white.
    /// A scene added through the catalog is one too, from its five colours.
    public static func light(
        accent: SRGBColor, subtle: SRGBColor, text: SRGBColor, floor: SRGBColor, onAccent: SRGBColor = Palette.white
    ) -> SceneColors {
        SceneColors(
            accent: accent, accentSubtle: subtle, onAccent: onAccent, accentText: text, floor: floor,
            onFloor: Palette.ink, ring: accent, kindFill: subtle,
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
    /// The words of an action that can't be taken back, such as 解雇 and 确认解雇. The button
    /// keeps its shape; only its words turn red. Never a fill, never for errors.
    case fgDanger
    /// The tag a limited store wears (冬季限定), the same for every limit unless its data names
    /// another. Never changes with the scene.
    case bgLimited
    /// The words on `bgLimited`.
    case fgOnLimited

    /// The brand's colour: primary buttons and selection on brand screens. Never changes with the scene.
    case bgBrand
    /// Labels and icons on `bgBrand`.
    case fgOnBrand

    /// The scene's accent: primary buttons and selection on scene screens, nothing else.
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

    /// The brand's light gym, the same in every scene: the open screen's page, its floor and
    /// the floor's tile lines, as on the website. The tile lines also draw the court in 我's
    /// card window.
    case bgBrandPage
    case bgBrandFloor
    case borderBrandFloor

    /// The character's ticket in the editor, the same in every scene: its stub under the tear
    /// line, the lamp over the character, the sign-up date and the pen by the nickname. The
    /// ticket itself is `bgBrand`, and its light and lines are `fgOnBrand`.
    case bgBrandStub
    case bgBrandLamp
    case fgBrandStamp
    case fgBrandPen

    /// The color this role takes in a scene.
    public func color(in theme: SceneTheme) -> SRGBColor {
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
        case .fgDanger: .fixed(Palette.danger)
        case .bgLimited: .fixed(Palette.limited)
        case .fgOnLimited: .fixed(Palette.white)
        case .bgBrand: .fixed(Palette.brand)
        case .fgOnBrand: .fixed(Palette.onBrand)
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
        case .bgBrandPage: .fixed(Palette.brandSky)
        case .bgBrandFloor: .fixed(Palette.brandFloor)
        case .borderBrandFloor: .fixed(Palette.brandTile)
        case .bgBrandStub: .fixed(Palette.brandStub)
        case .bgBrandLamp: .fixed(Palette.brandLamp)
        case .fgBrandStamp: .fixed(Palette.brandStamp)
        case .fgBrandPen: .fixed(Palette.brandPen)
        }
    }
}

/// Whose colour a screen's primary button and selection marks wear. Brand screens (opening,
/// sign-up, 我, the tab bar, writing a post, 请假条, the feed) use `.brand`; the squad's own turf
/// (home, the check-in burst, the 出赛表 poster, 战报) uses `.scene`. 我's 设置 and 注销账号
/// pages stay ink and white, so they use `.ink`.
public enum AccentTone: Sendable {
    case scene
    case brand
    case ink

    /// The solid fill: a primary button, a check badge, a picked border, a switch that is on.
    public var fill: ColorRole {
        switch self {
        case .scene: .bgAccent
        case .brand: .bgBrand
        case .ink: .fgDefault
        }
    }

    /// Labels and icons on `fill`.
    public var onFill: ColorRole {
        switch self {
        case .scene: .fgOnAccent
        case .brand: .fgOnBrand
        case .ink: .bgCanvas
        }
    }
}
