import Testing

@testable import Contracts

@Test(arguments: ["❤️", "💪", "😂", "👍🏽", "🇨🇦", "👩‍👩‍👧", "1️⃣", "🤤"])
func oneEmojiIsAnEmoji(_ text: String) throws {
    #expect(try Emoji(text).text == text)
}

@Test(arguments: ["", "a", "1", "#", "好", "😂😂", "❤️ ", "ok"])
func anythingElseIsRefused(_ text: String) {
    #expect(throws: ContractsError.notAnEmoji(text)) { try Emoji(text) }
}

@Test func theDoubleTapHeartIsAnEmoji() throws {
    #expect(try Emoji("❤️") == .heart)
}
