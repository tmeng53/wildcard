import Testing

@testable import DesignSystem

/// The winter 雪场: glacier navy with ice blue on it, a pale ice floor.
@Test func skiIsGlacierNavy() {
    let colors = SceneTheme.ski.colors
    let roles = [
        colors.accent, colors.accentSubtle, colors.onAccent, colors.accentText, colors.floor, colors.onFloor,
        colors.ring, colors.kindFill, colors.kindFillOnFloor, colors.kindInk,
    ].map(\.hex)
    #expect(
        roles == [
            "#16384D", "#EAF7FD", "#D6F1FB", "#16384D", "#D7ECF6", "#22252E", "#16384D", "#EAF7FD", "#FFFFFF",
            "#16384D",
        ])
}
