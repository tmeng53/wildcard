import Testing

@testable import DesignSystem

/// The ink surface 我's player card stands on, and the ink tone of the 设置 and 注销账号 pages.
struct InkSurfaceTests {
    @Test func inkSurfaceMatchesTheApprovedCard() {
        let ink: [ColorRole] = [.bgInk, .fgOnInk, .fgOnInkMuted, .borderOnInk]
        #expect(ink.map { $0.color(in: .gym).hex } == ["#22252E", "#FFFFFF", "#AEB2BC", "#3A3E49"])
    }

    @Test(arguments: [ColorRole.fgOnInk, .fgOnInkMuted])
    func textOnInkIsReadable(text: ColorRole) {
        #expect(text.color(in: .gym).contrastRatio(with: ColorRole.bgInk.color(in: .gym)) >= 4.5)
    }

    @Test func theInkToneIsInkWithAWhiteLabel() {
        #expect([AccentTone.ink.fill, AccentTone.ink.onFill] == [.fgDefault, .bgCanvas])
    }
}
