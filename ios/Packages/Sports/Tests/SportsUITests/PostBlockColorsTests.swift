#if os(iOS)
import Contracts
import DesignSystem
import SportsUI
import Testing

/// No post block is the brand's graphite: a run of them turned 我的动态 into black squares.
@Test(arguments: CheckInKind.allCases)
func noPostBlockIsGraphite(kind: CheckInKind) {
    let colors = PostBlockColors(kind: kind, activity: nil)
    #expect(colors.fill == .bgAccent)
    #expect(colors.ink == .fgOnAccent)
}

@Test func aDisclaimerTakesTheGymsSteel() {
    #expect(PostBlockColors(kind: .disclaimer, activity: nil).scene == .gym)
}
#endif
