/// Weights PingFang SC ships. It has no bold or heavier cut, so `semibold` is the heaviest
/// Chinese weight; asking for more would silently fall back.
public enum TextWeight: Sendable, Hashable {
    case regular
    case medium
    case semibold
}

/// Weights of the bundled Barlow Condensed cuts.
public enum ScoreboardWeight: Sendable, Hashable {
    case semibold
    case bold
    case extraBold
}

/// A typeface and weight. Only bundled or system cuts are representable.
public enum Face: Sendable, Hashable {
    /// PingFang SC: all Chinese and Latin running text, so mixed names share one design.
    case text(TextWeight)
    /// Barlow Condensed: scoreboard numbers, week numbers, bibs and short Latin labels.
    case scoreboard(ScoreboardWeight)

    public var postScriptName: String {
        switch self {
        case .text(.regular): "PingFangSC-Regular"
        case .text(.medium): "PingFangSC-Medium"
        case .text(.semibold): "PingFangSC-Semibold"
        case .scoreboard(.semibold): "BarlowCondensed-SemiBold"
        case .scoreboard(.bold): "BarlowCondensed-Bold"
        case .scoreboard(.extraBold): "BarlowCondensed-ExtraBold"
        }
    }
}

/// The system text style a type style scales with under Dynamic Type.
public enum ScaleAnchor: Sendable, Hashable {
    case largeTitle, title, title2, title3, headline, body, callout, subheadline, footnote, caption
}

/// One rung of the type ramp, in points at the default Dynamic Type size.
public struct TypeStyle: Sendable, Hashable {
    public let face: Face
    public let size: Double
    /// Extra space between letters, in points.
    public let tracking: Double
    public let anchor: ScaleAnchor

    public init(face: Face, size: Double, tracking: Double = 0, anchor: ScaleAnchor) {
        self.face = face
        self.size = size
        self.tracking = tracking
        self.anchor = anchor
    }
}

/// The type ramp. Chinese tops out at Semibold, so levels come from size, not weight.
/// One `hero` per screen; scoreboard styles carry the numbers that matter most.
public enum TypeRamp {
    public static let hero = TypeStyle(face: .text(.semibold), size: 30, anchor: .largeTitle)
    public static let title = TypeStyle(face: .text(.semibold), size: 24, anchor: .title)
    /// Squad names, card titles and the main button.
    public static let headline = TypeStyle(face: .text(.semibold), size: 17, anchor: .headline)
    public static let body = TypeStyle(face: .text(.regular), size: 16, anchor: .body)
    /// Draft cards, capsule labels and chips.
    public static let callout = TypeStyle(face: .text(.medium), size: 15, anchor: .callout)
    /// Tabs, name tags and reaction buttons.
    public static let caption = TypeStyle(face: .text(.medium), size: 13, anchor: .caption)
    /// Capsule badges such as 第 42 周 and 我 · 本周.
    public static let footnote = TypeStyle(face: .text(.semibold), size: 12, anchor: .footnote)

    /// The big number on a highlight card.
    public static let scoreHero = TypeStyle(
        face: .scoreboard(.extraBold), size: 92, tracking: -1.84, anchor: .largeTitle)
    /// The squad's week score, like a broadcast score bug.
    public static let scoreLarge = TypeStyle(face: .scoreboard(.extraBold), size: 52, anchor: .largeTitle)
    /// The `/25` after `scoreLarge`, in tertiary ink.
    public static let scoreLargeDenominator = TypeStyle(face: .scoreboard(.extraBold), size: 28, anchor: .title)
    /// Podium counts in the Sunday recap.
    public static let scoreMedium = TypeStyle(face: .scoreboard(.extraBold), size: 30, anchor: .title)
    /// 我 · 本周 `3/5`.
    public static let scoreSmall = TypeStyle(face: .scoreboard(.extraBold), size: 20, anchor: .title3)
    /// The `/5` after `scoreSmall`, in tertiary ink.
    public static let scoreSmallDenominator = TypeStyle(face: .scoreboard(.extraBold), size: 14, anchor: .footnote)
    /// Short uppercase Latin labels: `WK42`, `LANE 3`.
    public static let scoreLabel = TypeStyle(face: .scoreboard(.semibold), size: 14, tracking: 1.5, anchor: .caption)

    public static let all: [(name: String, style: TypeStyle)] = [
        ("hero", hero), ("title", title), ("headline", headline), ("body", body),
        ("callout", callout), ("caption", caption), ("footnote", footnote), ("scoreHero", scoreHero),
        ("scoreLarge", scoreLarge), ("scoreLargeDenominator", scoreLargeDenominator),
        ("scoreMedium", scoreMedium), ("scoreSmall", scoreSmall),
        ("scoreSmallDenominator", scoreSmallDenominator), ("scoreLabel", scoreLabel),
    ]
}
