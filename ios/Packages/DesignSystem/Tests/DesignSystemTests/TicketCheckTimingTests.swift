import Testing

@testable import DesignSystem

struct TicketCheckTimingTests {
    @Test func startsAsTheLogoAndEndsOnTheCheck() {
        #expect(TicketCheckTiming.frame(at: 0) == .init(rock: 0, letter: 1, check: 0, words: 0))
        #expect(TicketCheckTiming.frame(at: 1.43) == .done)
        #expect(TicketCheckTiming.frame(at: 9) == .done)
    }

    @Test func bouncesFirstThenSwapsTheWForTheCheck() {
        let top = TicketCheckTiming.frame(at: 0.3)
        #expect(top.rock > 0.9)
        #expect(top.letter == 1)
        #expect(top.check == 0)
        let swapping = TicketCheckTiming.frame(at: 0.9)
        #expect(swapping.rock == 0)
        #expect(swapping.letter > 0 && swapping.letter < 0.2)
        #expect(swapping.check > 0 && swapping.check < 0.2)
        #expect(swapping.words == 0)
        let after = TicketCheckTiming.frame(at: 1.2)
        #expect(after.letter == 0)
        #expect(after.check > 0.9)
        #expect(after.words > 0 && after.words < 1)
    }
}
