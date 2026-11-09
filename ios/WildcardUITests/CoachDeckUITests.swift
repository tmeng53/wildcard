import XCTest

/// The coach's page as the approved deck has it (Tracy, 2026-11-08): with a morning note waiting,
/// the phone in 毛头's hand shows a dot and the note never slides up over 今天 by itself; a tap on
/// 毛头 opens its page, a stack of what it has for me, oldest on top. Each card is swiped right
/// into 以前; a gift opens in place (拆开, then 立刻穿上) and a challenge is answered in place
/// (接受挑战). Once all are seen, 看以前的 opens 以前, where every card is a row. Screenshots are
/// kept for review.
@MainActor
final class CoachDeckUITests: XCTestCase {
    private static let wait: TimeInterval = 30

    func testEveryCardIsSeenInTurnAndGoesIntoEarlier() {
        continueAfterFailure = false
        let app = launch()
        let checkIn = app.buttons["today.checkin"]
        XCTAssertTrue(checkIn.waitForExistence(timeout: Self.wait), "the home didn't open")
        let coach = app.buttons["today.coach"]
        XCTAssertTrue(coach.waitForExistence(timeout: Self.wait), "毛头 isn't on the sideline")
        expectation(for: NSPredicate(format: "value == %@", "有新消息"), evaluatedWith: coach)
        waitForExpectations(timeout: Self.wait)
        XCTAssertTrue(checkIn.isHittable, "打卡 is covered")
        keepScreenshot(named: "105-coach-note-waiting")

        coach.tap()
        // 对小队说: 去动态看看.
        let board = card("board", in: app)
        XCTAssertTrue(board.waitForExistence(timeout: Self.wait), "the page didn't open on the line to the squad")
        assertOnScreen(board, app.buttons["coachDeck.feed"], in: app)
        keepScreenshot(named: "106-coach-deck-board")
        putAway(board, in: app)

        // 今天对你说: no button, only the swipe.
        let note = card("note", in: app)
        XCTAssertTrue(note.waitForExistence(timeout: Self.wait), "the morning note isn't next")
        keepScreenshot(named: "107-coach-deck-note")
        putAway(note, in: app)

        openAndWear(in: app)
        accept(in: app)
        // The coach's lines to my check-ins stay under the posts in 动态, never here.

        // All seen: 看以前的 opens 以前, newest first.
        let allSeen = element("coachDeck.allSeen", in: app)
        XCTAssertTrue(allSeen.waitForExistence(timeout: Self.wait), "the last card isn't 暂时没有新消息")
        let earlier = app.buttons["coachDeck.earlier"]
        assertOnScreen(allSeen, earlier, in: app)
        keepScreenshot(named: "113-coach-deck-all-seen")
        earlier.tap()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "coachEarlier.row."))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: Self.wait), "以前 didn't open")
        XCTAssertEqual(rows.count, 4, "以前 doesn't list every card seen")
        XCTAssertEqual(rows.firstMatch.identifier, "coachEarlier.row.challenge", "以前 isn't newest first")
        keepScreenshot(named: "114-coach-earlier")
    }

    /// 不接挑战 with a word to 毛头 on why: the field and 不接挑战 stay above the keyboard while it
    /// is typed, and the card goes once it is sent.
    func testTheReasonForPassingStaysAboveTheKeyboard() {
        continueAfterFailure = false
        let app = launch()
        let coach = app.buttons["today.coach"]
        XCTAssertTrue(coach.waitForExistence(timeout: Self.wait), "毛头 isn't on the sideline")
        coach.tap()
        for kind in ["board", "note", "gift"] {
            let next = card(kind, in: app)
            XCTAssertTrue(next.waitForExistence(timeout: Self.wait), "the \(kind) isn't next")
            putAway(next, in: app)
        }
        let challenge = card("challenge", in: app)
        let reason = element("coachDeck.reason", in: app)
        XCTAssertTrue(reason.waitForExistence(timeout: Self.wait), "the challenge has no field for why")
        XCTAssertEqual(reason.placeholderValue, "告诉毛头为什么（可选）")
        reason.tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: Self.wait), "the keyboard isn't up")
        reason.typeText("我鸡蛋过敏")
        Thread.sleep(forTimeInterval: 1)
        let decline = app.buttons["coachDeck.decline"]
        XCTAssertLessThanOrEqual(reason.frame.maxY, keyboard.frame.minY, "the keyboard covers the field")
        XCTAssertLessThanOrEqual(decline.frame.maxY, keyboard.frame.minY, "the keyboard covers 不接挑战")
        XCTAssertTrue(decline.isHittable, "不接挑战 is covered")
        keepScreenshot(named: "116-coach-deck-challenge-reason")
        decline.tap()
        waitFor(challenge, "exists == false", "the challenge stayed after 不接挑战")
    }

    /// A gift swiped away in its box stays boxed in 以前, and opens from there.
    func testAGiftSwipedAwayBoxedOpensFromEarlier() {
        continueAfterFailure = false
        let app = launch(extra: ["-uitest-coach-seen"])
        let coach = app.buttons["today.coach"]
        XCTAssertTrue(coach.waitForExistence(timeout: Self.wait), "毛头 isn't on the sideline")
        coach.tap()
        let history = app.buttons["coachDeck.history"]
        XCTAssertTrue(history.waitForExistence(timeout: Self.wait), "the page has no 以前")
        history.tap()
        let gift = app.buttons["coachEarlier.row.gift"]
        XCTAssertTrue(gift.waitForExistence(timeout: Self.wait), "以前 has no gift")
        gift.tap()
        let unwrap = app.buttons["coachDeck.unwrap"]
        XCTAssertTrue(unwrap.waitForExistence(timeout: Self.wait), "the boxed gift doesn't open from 以前")
        assertOnScreen(card("gift", in: app), unwrap, in: app)
        unwrap.tap()
        app.buttons["coachDeck.later"].tap()
        XCTAssertTrue(
            app.buttons["coachDeck.wardrobe"].waitForExistence(timeout: Self.wait), "一会儿再说 didn't put it away")
        keepScreenshot(named: "115-coach-earlier-gift-later")
    }

    /// 送你的: 拆开, then 立刻穿上, then 去衣橱看看.
    private func openAndWear(in app: XCUIApplication) {
        let gift = card("gift", in: app)
        XCTAssertTrue(gift.waitForExistence(timeout: Self.wait), "the gift isn't next")
        let unwrap = app.buttons["coachDeck.unwrap"]
        assertOnScreen(gift, unwrap, in: app)
        keepScreenshot(named: "108-coach-deck-gift")
        unwrap.tap()
        let wear = app.buttons["coachDeck.wear"]
        XCTAssertTrue(wear.waitForExistence(timeout: Self.wait), "拆开 didn't offer 立刻穿上")
        XCTAssertTrue(app.buttons["coachDeck.later"].isHittable, "一会儿再说 is covered")
        Thread.sleep(forTimeInterval: 1)
        keepScreenshot(named: "109-coach-deck-gift-open")
        wear.tap()
        let wardrobe = app.buttons["coachDeck.wardrobe"]
        XCTAssertTrue(wardrobe.waitForExistence(timeout: Self.wait), "立刻穿上 didn't offer 去衣橱看看")
        Thread.sleep(forTimeInterval: 1)
        keepScreenshot(named: "110-coach-deck-gift-worn")
        putAway(gift, in: app)

    }

    /// 今日挑战: 接受挑战 answers it, stamps the button, and the card goes on its own.
    private func accept(in app: XCUIApplication) {
        let challenge = card("challenge", in: app)
        XCTAssertTrue(challenge.waitForExistence(timeout: Self.wait), "the challenge isn't next")
        let accept = app.buttons["coachDeck.accept"]
        assertOnScreen(challenge, accept, in: app)
        XCTAssertTrue(app.buttons["coachDeck.decline"].isHittable, "不接挑战 is covered")
        keepScreenshot(named: "111-coach-deck-challenge")
        accept.tap()
        waitFor(challenge, "exists == false", "the challenge stayed after it was accepted")

    }

    private func launch(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments +=
            [
                "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push", "-uitest-noon",
                "-today.cardPage", "0", "-uitest-coach-note",
            ] + extra
        app.launch()
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }
        return app
    }

    /// Swipes the top card right, into 以前.
    private func putAway(_ card: XCUIElement, in app: XCUIApplication) {
        card.swipeRight(velocity: .fast)
        waitFor(card, "exists == false", "the swipe didn't put \(card.identifier) away")
    }

    private func card(_ kind: String, in app: XCUIApplication) -> XCUIElement {
        element("coachDeck.card.\(kind)", in: app)
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// The card is all on screen, and its button is free and on it.
    private func assertOnScreen(_ card: XCUIElement, _ button: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(button.waitForExistence(timeout: Self.wait), "\(card.identifier) has no \(button.identifier)")
        let screen = app.windows.firstMatch.frame
        XCTAssertTrue(screen.contains(card.frame), "\(card.identifier) runs off the screen: \(card.frame)")
        XCTAssertTrue(card.frame.contains(button.frame), "\(button.identifier) runs off its card")
        XCTAssertTrue(button.isHittable, "\(button.identifier) is covered")
    }

    private func waitFor(_ element: XCUIElement, _ format: String, _ message: String) {
        let met = expectation(for: NSPredicate(format: format), evaluatedWith: element)
        XCTAssertEqual(XCTWaiter.wait(for: [met], timeout: Self.wait), .completed, message)
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
