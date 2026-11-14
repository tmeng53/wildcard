import Contracts
import Testing

private func words(_ zhHans: String) -> CatalogNames {
    CatalogNames(simplifiedChinese: zhHans, english: zhHans, traditionalChinese: zhHans)
}

/// 喜欢外卡吗？ 喜欢 → 给外卡写个评价？ (写评价 opens the App Store, then closes) | 不太喜欢 → 哪里不好用？
/// (a box, 发送 sends it and closes) | 看看 (opens 动态, stays).
private let enjoying = CoachMessage(cards: [
    CoachMessage.Card(
        path: "", line: words("喜欢外卡吗？"),
        buttons: [
            CoachMessage.Button(id: "yes", label: words("喜欢"), style: .primary, tap: [.next("yes")]),
            CoachMessage.Button(id: "no", label: words("不太喜欢"), tap: [.next("no")]),
            CoachMessage.Button(id: "look", label: words("看看"), style: .plain, tap: [.open("feed")]),
        ]),
    CoachMessage.Card(
        path: "yes", line: words("给外卡写个评价？"),
        buttons: [
            CoachMessage.Button(
                id: "review", label: words("写评价"), tap: [.open("https://apps.apple.com/app/id1"), .close])
        ], thanks: words("谢谢你！")),
    CoachMessage.Card(
        path: "no", line: words("哪里不好用？"), input: CoachMessage.Input(),
        buttons: [CoachMessage.Button(id: "send", label: words("发送"), tap: [.feedback("problem"), .close])]),
])

@Test func aMessageStartsOnItsFirstCard() {
    #expect(enjoying.place == .card(""))
}

@Test func aTapTurnsTheCardAndAClosingTapFoldsItToItsThanks() {
    #expect(enjoying.with(answered: ["": .init(tap: "no")]).place == .card("no"))
    #expect(
        enjoying.with(answered: ["": .init(tap: "no"), "no": .init(tap: "send", text: "太慢")]).place == .closed("no"))
    #expect(enjoying.with(answered: ["": .init(tap: "yes"), "yes": .init(tap: "review")]).place == .closed("yes"))
}

@Test func aTapThatOnlyOpensAPlaceStaysOnItsCard() {
    #expect(enjoying.with(answered: ["": .init(tap: "look")]).place == .card(""))
    // Stars or words alone don't move on.
    #expect(enjoying.with(answered: ["": .init(stars: 4)]).place == .card(""))
}

@Test func aTapOnAButtonOrCardTheMessageNoLongerHasStaysPut() {
    #expect(enjoying.with(answered: ["": .init(tap: "maybe")]).place == .card(""))
    let gone = CoachMessage(cards: [enjoying.cards[0]], answered: ["": .init(tap: "yes")])
    #expect(gone.place == .card(""))
}

@Test func typedWordsAreTrimmedAndCut() {
    #expect(CoachMessage.text("  器械很新  ") == "器械很新")
    #expect(CoachMessage.text("   ") == nil)
    #expect(CoachMessage.text(String(repeating: "好", count: 600))?.count == CoachMessage.textLimit)
    // The API counts UTF-16 units: a family emoji is 11 of them and is never cut in half.
    let families = CoachMessage.text(String(repeating: "👨‍👩‍👧‍👦", count: 100))
    #expect(families?.utf16.count == 495)
    #expect(families?.count == 45)
    #expect(enjoying.cards[2].buttons[0].sendsFeedback)
    #expect(!enjoying.cards[0].buttons[0].sendsFeedback)
}
