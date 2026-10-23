/// Weights PingFang SC ships. It has no bold or heavier cut, so `semibold` is the heaviest
/// Chinese weight; asking for more would silently fall back.
public enum TextWeight: Sendable, Hashable {
    case regular
    case medium
    case semibold
}

/// Weights of the bundled Barlow Condensed cuts: numbers, their lighter denominators, and the
/// italic week number on the 出赛表 poster.
public enum ScoreboardWeight: Sendable, Hashable {
    case semibold
    case extraBold
    case extraBoldItalic
}

/// A typeface and weight. Only bundled or system cuts are representable.
public enum Face: Sendable, Hashable {
    /// PingFang SC: all Chinese and Latin running text, so mixed names share one design.
    case text(TextWeight)
    /// Barlow Condensed: numbers only.
    case scoreboard(ScoreboardWeight)

    public var postScriptName: String {
        switch self {
        case .text(.regular): "PingFangSC-Regular"
        case .text(.medium): "PingFangSC-Medium"
        case .text(.semibold): "PingFangSC-Semibold"
        case .scoreboard(.semibold): "BarlowCondensed-SemiBold"
        case .scoreboard(.extraBold): "BarlowCondensed-ExtraBold"
        case .scoreboard(.extraBoldItalic): "BarlowCondensed-ExtraBoldItalic"
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

/// The type ramp. Six text levels, each at least 4 points or one weight apart from the next;
/// Chinese tops out at Semibold, so levels come from size, not weight. Multi-line Chinese runs at
/// 1.5 line height. Barlow is for numbers only: one hero number per screen.
public enum TypeRamp {
    /// The name or title at the top of a tab's home: 32/40.
    public static let largeTitle = TypeStyle(face: .text(.semibold), size: 32, anchor: .largeTitle)
    /// The question at the top of a task step (平时练什么？): 26/34.
    public static let taskTitle = TypeStyle(face: .text(.semibold), size: 26, anchor: .title)
    /// Section titles: 22/30.
    public static let title = TypeStyle(face: .text(.semibold), size: 22, anchor: .title2)
    /// Card titles and squad names: 17/24.
    public static let headline = TypeStyle(face: .text(.semibold), size: 17, anchor: .headline)
    /// Body text and list rows: 16/24.
    public static let body = TypeStyle(face: .text(.regular), size: 16, anchor: .body)
    /// Text typed into a field.
    public static let field = TypeStyle(face: .text(.regular), size: 16, anchor: .body)
    /// The label of a pick row.
    public static let pick = TypeStyle(face: .text(.medium), size: 16, anchor: .body)
    /// Supporting text and the values at the end of a row: 13/18.
    public static let footnote = TypeStyle(face: .text(.regular), size: 13, anchor: .footnote)
    /// Tags and short emphasized notes (我 2/5).
    public static let footnoteEmphasis = TypeStyle(face: .text(.semibold), size: 13, anchor: .footnote)
    /// The small label over a number or a group, letter-spaced 0.04 em: 12/16.
    public static let label = TypeStyle(face: .text(.semibold), size: 12, tracking: 0.48, anchor: .caption)

    /// The primary button's label. Large enough to count as large text, so white on the brighter
    /// accents only needs 3:1.
    public static let action = TypeStyle(face: .text(.semibold), size: 19, anchor: .headline)
    /// Unselected switches and pills, and capsule labels.
    public static let callout = TypeStyle(face: .text(.medium), size: 15, anchor: .callout)
    /// A tab bar item's name; the selected one uses `tabSelected`.
    public static let tab = TypeStyle(face: .text(.medium), size: 12, anchor: .caption)
    public static let tabSelected = TypeStyle(face: .text(.semibold), size: 12, anchor: .caption)
    /// A small name under a tile (跑道 under its scene): 12, regular; picked, `tabSelected`.
    public static let caption = TypeStyle(face: .text(.regular), size: 12, anchor: .caption)
    /// Secondary and text buttons, and the selected switch or pill: `callout`, one weight heavier.
    public static let calloutEmphasis = TypeStyle(face: .text(.semibold), size: 15, anchor: .callout)

    /// The one hero number on a screen (the squad's 14/22).
    public static let scoreHero = TypeStyle(face: .scoreboard(.extraBold), size: 60, anchor: .largeTitle)
    /// A number on a card.
    public static let scoreCard = TypeStyle(face: .scoreboard(.extraBold), size: 32, anchor: .title)
    /// A number in a row.
    public static let scoreInline = TypeStyle(face: .scoreboard(.extraBold), size: 22, anchor: .title3)
    /// A count beside its label in a row of counts (健康餐 3): 18.
    public static let scoreSmall = TypeStyle(face: .scoreboard(.extraBold), size: 18, anchor: .body)
    /// A number inside a line of small text (小队 5 周前…): 14, semibold.
    public static let scoreCaption = TypeStyle(face: .scoreboard(.semibold), size: 14, anchor: .caption)

    /// The week's number across the 出赛表 poster (W42), italic and set tight. The poster is a
    /// picture saved at a fixed size, so it doesn't scale with Dynamic Type.
    public static let posterWeek = TypeStyle(
        face: .scoreboard(.extraBoldItalic), size: 128, tracking: -5, anchor: .largeTitle)

    /// The denominator after a number (`/22`): a weight lighter and a little over half the size.
    public static func denominator(of number: TypeStyle) -> TypeStyle {
        TypeStyle(face: .scoreboard(.semibold), size: (number.size * 0.55).rounded(), anchor: number.anchor)
    }

    public static let all: [(name: String, style: TypeStyle)] = [
        ("largeTitle", largeTitle), ("taskTitle", taskTitle), ("title", title), ("headline", headline),
        ("body", body), ("field", field), ("pick", pick), ("footnote", footnote),
        ("footnoteEmphasis", footnoteEmphasis), ("label", label), ("action", action), ("callout", callout),
        ("calloutEmphasis", calloutEmphasis), ("tab", tab), ("tabSelected", tabSelected), ("caption", caption),
        ("scoreHero", scoreHero),
        ("scoreCard", scoreCard),
        ("scoreInline", scoreInline), ("scoreSmall", scoreSmall), ("scoreCaption", scoreCaption),
        ("posterWeek", posterWeek),
    ]
}
