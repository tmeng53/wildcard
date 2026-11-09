import DesignSystem
import Testing

struct ZoneColorTests {
    @Test func zonesWearTheirLightenedSportColoursOnGraphite() {
        #expect((0..<4).map { ZoneColors.zone($0).hex } == ["#77C8D8", "#6DB394", "#D38649", "#E86458"])
        #expect(ZoneColors.zone(9).hex == "#E86458")
        #expect(ZoneColors.fill.hex == "#1F2128")
    }
}
