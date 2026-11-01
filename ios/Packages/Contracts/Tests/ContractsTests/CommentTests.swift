import Contracts
import Testing

@Test func aCommentIsTrimmedAndMaySpanLines() throws {
    #expect(try CommentText("  明天\n一起  ").text == "明天\n一起")
}

@Test func aCommentHoldsOneToAHundredCharacters() throws {
    #expect(try CommentText(String(repeating: "字", count: 100)).text.count == 100)
    #expect(throws: ContractsError.commentLength(101)) { try CommentText(String(repeating: "字", count: 101)) }
    #expect(throws: ContractsError.commentLength(0)) { try CommentText(" \n ") }
}
