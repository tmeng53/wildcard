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

    @Test func aNewLineCanBePostedAgain() {
        var entry = DisclaimerEntry()
        entry.write("今天不想动")
        entry.block()
        entry.write("下雨，场地条件不允许")
        #expect(!entry.isBlocked)
        #expect(entry.disclaimer?.text == "下雨，场地条件不允许")
    }

    @Test func aLineIsOneLineOfAtMostFortyCharacters() {
        var entry = DisclaimerEntry()
        entry.write("第一行\n" + String(repeating: "累", count: 45))
        #expect(entry.text == "第一行" + String(repeating: "累", count: 37))
        #expect(entry.text.count == 40)
        entry.write("   ")
        #expect(entry.disclaimer == nil)
    }
}
