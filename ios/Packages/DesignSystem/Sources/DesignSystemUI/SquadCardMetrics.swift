#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// Sizes that belong to the squad card alone.
enum SquadCardMetrics {
    /// Inside each page's padding: 186 tall with the card's padding, on both pages; the dots'
    /// row adds its own height under them.
    static let pageContent: Double = 186 - 2 * Space.cardPadding
    /// Between rings: eight 38-point rings fit a 358-point card.
    static let ringSpacing: Double = 3
    /// On a narrower phone (375 points), eight rings shrink to fit: 32-point rings, 1 apart.
    static let compactAvatar: Double = Sizing.characterHead - 6
    static let compactRingSpacing: Double = 1
    /// With 今天 before them on a 375-point phone, eight rings shrink a little more.
    static let narrowAvatar: Double = Sizing.characterHead - 10
    /// Between the goal's day cells; past 40 cells they sit closer.
    static let cellSpacing: Double = 2
    static let denseCellSpacing: Double = 1
    /// The second page's day circles.
    static let day: Double = 30
    static let dayGlyph: Double = 14
    static let badge: Double = 13
    static let badgeGlyph: Double = 7
    /// Today's circle is drawn in ink, a little heavier than a planned day's hairline ring.
    static let todayStroke: Double = 2
    /// The picked day's capsule behind its name.
    static let pick: Double = 20
    static let dot: Double = 6
    /// The folded capsule's day circles, the room between each and its name, its heads, the
    /// line between the squad and my week, and its height with the grabber under its content.
    static let compactDay: Double = 24
    static let compactDayGap: Double = 2
    /// The small home screen widget's day circles, seven across its narrow width.
    static let tinyDay: Double = 16
    static let capsuleHead: Double = 26
    static let capsuleDivider: Double = 36
    static let capsuleHeight: Double = 70
    /// The line between the squad and my week: faint ink, like the grabber.
    static let dividerOpacity = 0.12
    /// A drag starts this far from the touch; past `fold` points up (down, on the capsule) it
    /// folds (opens) the card, which follows the finger at `rubber` of the distance.
    static let dragStart: Double = 12
    static let fold: Double = 40
    static let rubber: Double = 0.35
}

extension DragGesture.Value {
    /// More up or down than sideways.
    var isVertical: Bool { abs(translation.height) > abs(translation.width) }
}

extension View {
    /// A page of the squad card: the card's whole width, the same height on both pages, with
    /// the card's padding except at its foot, where the dots sit.
    func squadCardPage() -> some View {
        frame(
            maxWidth: .infinity, minHeight: SquadCardMetrics.pageContent, maxHeight: .infinity, alignment: .topLeading
        )
        .padding([.top, .horizontal], Space.cardPadding)
        .padding(.bottom, Space.xs)
        .containerRelativeFrame(.horizontal)
    }
}
#endif
