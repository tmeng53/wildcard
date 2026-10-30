import Contracts
import Testing

@testable import CheckInUI

/// Rolls a fixed sequence, so a test knows which lines come out.
private struct Counting: RandomNumberGenerator {
    var state: UInt64 = 0
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        return state
    }
}

private let lines = [
    CatalogNames(simplifiedChinese: "腿说休息", english: "Legs said rest", traditionalChinese: "腿說休息"),
    CatalogNames(simplifiedChinese: "下雨了", english: "It rained", traditionalChinese: "下雨了"),
    CatalogNames(simplifiedChinese: "加班", english: "Overtime", traditionalChinese: "加班"),
    CatalogNames(simplifiedChinese: "累了", english: "Tired", traditionalChinese: "累了"),
]

@Test func theDiceRollDifferentLinesOfTheCatalogs() {
    var generator = Counting()
    let rolled = DiceDisclaimerWriter.roll(3, of: lines, using: &generator)
    #expect(rolled.count == 3)
    #expect(Set(rolled).count == 3)
    #expect(Set(rolled).isSubset(of: Set(lines.flatMap(\.all))))
}

@Test func theDiceRollNoMoreLinesThanTheyHave() {
    var generator = Counting()
    #expect(DiceDisclaimerWriter.roll(3, of: Array(lines.prefix(2)), using: &generator).count == 2)
    #expect(DiceDisclaimerWriter.roll(3, of: [], using: &generator).isEmpty)
}

@Test func theAppRollsTheLinesItWasLastShown() {
    let shown = DiceLines()
    shown.show(lines)
    #expect(shown.lines == lines)
    shown.show(Array(lines.prefix(1)))
    #expect(shown.lines == Array(lines.prefix(1)))
}
