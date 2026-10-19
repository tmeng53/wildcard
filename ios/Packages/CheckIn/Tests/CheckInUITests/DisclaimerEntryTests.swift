import Contracts
import Testing

@testable import CheckInUI

@Suite struct DisclaimerEntryTests {
    @Test func aBlockedReasonCantBePosted() {
        var entry = DisclaimerEntry()
        entry.write("今天不想动")
        #expect(entry.disclaimer?.text == "今天不想动")
        entry.block()
        #expect(entry.isBlocked)
        #expect(entry.disclaimer == nil)
        // Setting the same line again keeps it blocked.
        entry.write("今天不想动")
        #expect(entry.disclaimer == nil)
    }

    @Test func spacesAroundABlockedReasonKeepItBlocked() {
        var entry = DisclaimerEntry()
        entry.write("今天不想动")
        entry.block()
        entry.write("今天不想动 ")
        #expect(entry.isBlocked)
        #expect(entry.disclaimer == nil)
        entry.write(" 今天不想动")
        #expect(entry.disclaimer == nil)
    }

    @Test func aNewLineCanBePostedAgain() {
        var entry = DisclaimerEntry()
        entry.write("今天不想动")
        entry.block()
        entry.write("下雨，场地条件不允许")
        #expect(!entry.isBlocked)
        #expect(entry.disclaimer?.text == "下雨，场地条件不允许")
    }

    @Test func aLineIsOneLineOfAtMostEightyCharacters() {
        var entry = DisclaimerEntry()
        entry.write("第一行\n" + String(repeating: "累", count: 85))
        #expect(entry.text == "第一行" + String(repeating: "累", count: 77))
        #expect(entry.text.count == 80)
        entry.write("   ")
        #expect(entry.disclaimer == nil)
    }
}

@Suite struct DisclaimerEntrySuggestionTests {
    @Test func aSuggestedLineKeepsTheMembersWords() {
        var entry = DisclaimerEntry()
        entry.write("deadline")
        entry.suggest("今天是战略性休息")
        #expect(entry.text == "今天是战略性休息")
        #expect(entry.mine == "deadline")
        #expect(entry.canRestore)
        entry.restore()
        #expect(entry.text == "deadline")
        #expect(!entry.canRestore)
    }

    @Test func nothingToRestoreWhenNothingWasTyped() {
        var entry = DisclaimerEntry()
        entry.suggest("今天是战略性休息")
        #expect(!entry.canRestore)
        #expect(entry.disclaimer?.text == "今天是战略性休息")
    }

    @Test func aSuggestedLineCanBePostedAfterABlock() {
        var entry = DisclaimerEntry()
        entry.write("今天不想动")
        entry.block()
        entry.suggest("下雨，场地条件不允许")
        #expect(entry.disclaimer?.text == "下雨，场地条件不允许")
    }
}

struct DisclaimerRefillTests {
    @Test func theWritersNewLinesComeFirstAndEachOnce() {
        let lines = DisclaimerEntry.newLines(
            from: ["身体说不", "身体说不", "下雨了", "腿还没回来"], spare: ["加班到十点"], shown: ["下雨了"])
        #expect(lines == ["身体说不", "腿还没回来", "加班到十点"])
    }

    @Test func aRefillWithNothingNewFromTheWriterStillOffersNewLines() {
        let shown: Set<String> = ["下雨了", "身体说不", "腿还没回来"]
        let lines = DisclaimerEntry.newLines(
            from: ["下雨了", "身体说不", "腿还没回来"], spare: ["身体说不", "加班到十点", "战略性休息", "有氧"],
            shown: shown)
        #expect(lines == ["加班到十点", "战略性休息", "有氧"])
    }

    @Test func linesAreFittedAndEmptyOnesDropped() {
        let lines = DisclaimerEntry.newLines(from: ["第一行\n第二行", "\n"], spare: [], shown: [])
        #expect(lines == ["第一行第二行"])
    }
}
