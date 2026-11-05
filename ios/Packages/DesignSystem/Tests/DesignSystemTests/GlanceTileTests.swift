import DesignSystem
import Testing

struct GlanceTileTests {
    /// 我's 出赛表 tile writes the week as the poster does (W45), at a card number's size.
    @Test func theWeekIsThePostersItalicAtCardSize() {
        #expect(TypeRamp.scoreWeek.face == TypeRamp.posterWeek.face)
        #expect(TypeRamp.scoreWeek.size == TypeRamp.scoreCard.size)
    }
}
