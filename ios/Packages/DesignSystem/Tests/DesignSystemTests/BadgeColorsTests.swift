import Testing

@testable import DesignSystem

/// A 头衔徽章 in the tone the catalog sent: flat tones of that one colour, for the 软糖厚章.
@Test func badgeTakesTheCatalogTone() {
    let colors = BadgeColors(colour: "lavender", tone: "#9062DE")
    #expect(
        [colors.face, colors.side, colors.lit, colors.shade].map(\.hex) == ["#9062DE", "#4F367A", "#BCA1EB", "#7650B6"])
}

/// From a server before tones, a badge takes the colour of the scene its id names, else the gym's.
@Test func badgeWithoutToneTakesItsScene() {
    #expect(BadgeColors(colour: "track", tone: nil).face.hex == "#E65345")
    #expect(BadgeColors(colour: "honey", tone: nil).face.hex == "#4A6C8C")
    #expect(BadgeColors(colour: "track", tone: "red").face.hex == "#E65345")
}
