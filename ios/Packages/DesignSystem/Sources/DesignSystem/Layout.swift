/// Spacing on a 4-point grid.
public enum Space {
    public static let xxs: Double = 4
    public static let xs: Double = 8
    public static let s: Double = 12
    public static let m: Double = 16
    public static let l: Double = 24
    public static let xl: Double = 32
    public static let xxl: Double = 48
    /// Side margin of a full-width screen.
    public static let gutter: Double = 16
}

/// Corner radii, drawn as continuous (squircle) corners.
public enum Radius {
    /// Choice tiles in a picker grid.
    public static let tile: Double = 13
    /// Sport chips.
    public static let s: Double = 14
    /// Draft cards and text fields.
    public static let m: Double = 16
    /// Primary buttons.
    public static let button: Double = 18
    /// The squad banner.
    public static let l: Double = 24
    /// Highlight cards and glass cards.
    public static let xl: Double = 26

    /// Capsules (打卡, tabs, chips): half the height, so the ends are fully round.
    public static func capsule(height: Double) -> Double {
        height / 2
    }
}

/// Fixed control sizes, in points at the default Dynamic Type size.
public enum Sizing {
    /// Height of the 打卡 glass button.
    public static let checkInHeight: Double = 50
    /// Height of a check-in capsule.
    public static let capsuleHeight: Double = 44
    /// The frame of the icon inside a check-in capsule.
    public static let capsuleIcon: Double = 22
    /// The SF Symbol point size drawn inside `capsuleIcon`.
    public static let capsuleGlyph: Double = 17.6
    /// The smallest tap target, even when a control draws smaller.
    public static let minimumTapTarget: Double = 44

    // MARK: Pickers

    /// Height of a search field.
    public static let searchFieldHeight: Double = 44
    /// The drawn height of a compact choice pill. Its tap target stays `minimumTapTarget`.
    public static let pillHeight: Double = 36
    /// The SF Symbol point size inside a choice pill.
    public static let pillGlyph: Double = 15
    /// Height of a choice tile in a picker grid.
    public static let tileHeight: Double = 86
    /// The SF Symbol point size on a choice tile.
    public static let tileGlyph: Double = 28
    /// The solid check badge in the corner of a selected tile.
    public static let checkBadge: Double = 18
    /// The drawn height of the selected item's pill in a category bar.
    public static let categoryPillHeight: Double = 34
    /// Leading and trailing padding of every category bar item, so the items space evenly.
    public static let categoryItemInset: Double = 14
    /// The signature border of a selected pill or tile.
    public static let selectionStroke: Double = 1.75
}
