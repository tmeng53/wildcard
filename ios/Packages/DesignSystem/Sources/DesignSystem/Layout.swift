/// Spacing: seven steps on a 4-point grid, and the named uses screens take them by.
public enum Space {
    public static let xxs: Double = 4
    public static let xs: Double = 8
    public static let s: Double = 12
    public static let m: Double = 16
    public static let l: Double = 24
    public static let xl: Double = 32
    public static let xxl: Double = 48

    /// The page's left and right margin.
    public static let pageMargin: Double = m
    /// Inside a card.
    public static let cardPadding: Double = m
    /// Between cards.
    public static let cardGap: Double = s
    /// From a label to what it labels.
    public static let labelGap: Double = xs
    /// Between sections.
    public static let sectionGap: Double = xl
    /// From the header to the first block of content.
    public static let headerGap: Double = l
}

/// Corner radii, drawn as continuous (squircle) corners: crisp, not soft. Only buttons are
/// capsules.
public enum Radius {
    /// Thumbnails and small pictures.
    public static let thumbnail: Double = 6
    /// Pick rows, picture tiles and inputs.
    public static let pick: Double = 10
    /// Cards.
    public static let card: Double = 12
    /// The character's ticket in the editor.
    public static let ticket: Double = 14

    /// Capsules (buttons, pills, tags): half the height, so the ends are fully round.
    public static func capsule(height: Double) -> Double {
        height / 2
    }

    /// The radius of a shape inset in another, so the two curves stay concentric.
    public static func concentric(outer: Double, inset: Double) -> Double {
        max(outer - inset, 0)
    }
}

/// Fixed sizes, in points at the default Dynamic Type size.
public enum Sizing {
    // MARK: Controls: three heights

    /// The primary button, one per screen.
    public static let primaryControl: Double = 52
    /// Ordinary buttons, inputs and header buttons.
    public static let control: Double = 44
    /// Tags, pills and switches. Their tap target stays `minimumTapTarget`.
    public static let compactControl: Double = 36
    /// The smallest tap target, even when a control draws smaller.
    public static let minimumTapTarget: Double = 44

    // MARK: Picks

    /// A pick row: one choice in a list or a two-column grid.
    public static let pickRow: Double = 52
    /// The solid check on a selected pick.
    public static let checkBadge: Double = 20
    /// The accent border of a selected pick.
    public static let selectionStroke: Double = 1.5
    /// The border of an unselected pick, a field or a hairline divider.
    public static let hairline: Double = 1
    /// A color swatch.
    public static let swatch: Double = 32
    /// A switch: a capsule with a white knob inset from its edge.
    public static let switchWidth: Double = 51
    public static let switchHeight: Double = 31
    public static let switchKnobInset: Double = 2

    // MARK: Icons

    /// Icons in rows, picks and header buttons.
    public static let icon: Double = 20
    /// Icons inside pills and fields.
    public static let smallIcon: Double = 15

    // MARK: Check-in kinds

    /// A check-in kind button: a circle.
    public static let kindButton: Double = 52
    /// The icon on a kind button and on a check-in capsule.
    public static let kindIcon: Double = 22
    /// A tag's height.
    public static let tag: Double = 28

    // MARK: Progress and status

    /// A progress bar's and a step segment's thickness.
    public static let progress: Double = 4
    /// The width of a status ring.
    public static let ringWidth: Double = 3
    /// The white gap between a status ring and the avatar inside it.
    public static let ringGap: Double = 2

    // MARK: The character: three sizes only

    /// A head in an avatar circle.
    public static let characterHead: Double = 28
    /// From the waist up, beside a task title.
    public static let characterBust: Double = 84
    /// Full height, on 我 and the stage.
    public static let characterFull: Double = 132
}
