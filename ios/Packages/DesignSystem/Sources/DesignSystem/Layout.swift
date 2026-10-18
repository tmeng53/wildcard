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
}
