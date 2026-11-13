import Testing

@testable import DesignSystem

/// The 软糖星 starts at its top point and fits its square with its outline and thickness.
@Test func jellyStarFitsItsSquare() {
    let corners = JellyStarShape.corners
    #expect(corners.count == 10)
    #expect(abs(corners[0].x - 16) < 0.001 && abs(corners[0].y - 3.8) < 0.001)
    let rounding = JellyStarShape.roundingWidth / 2
    let top = corners.map(\.y).min()! - rounding
    let bottom = corners.map(\.y).max()! + rounding + JellyStarShape.depth
    let left = corners.map(\.x).min()! - rounding
    let right = corners.map(\.x).max()! + rounding
    #expect(top >= 0 && left >= 0 && bottom <= JellyStarShape.side && right <= JellyStarShape.side)
}

/// Lit stars are the approved gold; stars not lit are a soft grey.
@Test func jellyStarColours() {
    #expect(
        [Palette.starGold, Palette.starGoldSide, Palette.starGoldShine, Palette.starEmpty, Palette.starEmptySide]
            .map(\.hex) == ["#FFC21A", "#E09400", "#FFF4C7", "#EEF0F3", "#D9DDE3"])
}
