import XCTest

/// Coach messages (教练消息卡, Tracy 2026-11-12) on the coach's page: cards an admin wrote, one
/// template filled by data. 喜欢外卡吗？'s 不太喜欢 turns it into 哪里不好用？ with a box, whose 发送
/// waits for something typed, sends it as 意见反馈 and folds the card to its thanks; the next card
/// has the squad on its stage, what it is about, 软糖星 and a box. Screenshots are kept for review.
@MainActor
final class CoachMessageUITests: XCTestCase {
    private static let wait: TimeInterval = 30

    func testAMessageTurnsToItsNextCardAndFoldsToItsThanks() {
        continueAfterFailure = false
        let app = launch()
        let coach = app.buttons["today.coach"]
        XCTAssertTrue(coach.waitForExistence(timeout: Self.wait), "毛头 isn't on the sideline")
        coach.tap()

        let card = element("coachDeck.card.message", in: app)
        XCTAssertTrue(card.waitForExistence(timeout: Self.wait), "the page didn't open on the message")
        // The top card leans right and back once as the page opens; let it settle first.
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertTrue(text("喜欢外卡吗？", in: app).exists, "the message doesn't say its line")
        assertOnScreen(card, app.buttons["coachDeck.button.yes"], in: app)
        assertOnScreen(card, app.buttons["coachDeck.button.no"], in: app)
        keepScreenshot(named: "150-coach-message")

        app.buttons["coachDeck.button.no"].tap()
        XCTAssertTrue(text("哪里不好用？", in: app).waitForExistence(timeout: Self.wait), "不太喜欢 didn't turn the card")
        let send = app.buttons["coachDeck.button.send"]
        assertOnScreen(card, send, in: app)
        XCTAssertFalse(send.isEnabled, "发送 works with nothing typed")
        let box = element("coachDeck.box", in: app)
        box.tap()
        box.typeText("打卡页有点卡")
        XCTAssertTrue(send.isEnabled, "发送 doesn't work once something is typed")
        // The keyboard is up: the box and 发送 stay above it.
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: Self.wait), "the keyboard didn't come up")
        XCTAssertLessThanOrEqual(send.frame.maxY, keyboard.frame.minY, "发送 is under the keyboard")
        XCTAssertLessThanOrEqual(box.frame.maxY, keyboard.frame.minY, "the box is under the keyboard")
        keepScreenshot(named: "151-coach-message-box")

        send.tap()
        XCTAssertTrue(
            text("收到，谢谢你。", in: app).waitForExistence(timeout: Self.wait), "the card didn't fold to its thanks")
        XCTAssertFalse(send.exists, "a closed card still has its buttons")
        keepScreenshot(named: "152-coach-message-thanks")

        // Swiped away, the next message: the squad on its stage, 软糖星 and a box.
        card.swipeRight(velocity: .fast)
        XCTAssertTrue(
            text("周四去的 Equinox，打个分？", in: app).waitForExistence(timeout: Self.wait), "the next message isn't up")
        let stars = element("coachDeck.stars", in: app)
        XCTAssertTrue(stars.waitForExistence(timeout: Self.wait), "the card has no stars")
        XCTAssertTrue(element("coachDeck.about", in: app).exists, "the card doesn't say what it is about")
        assertOnScreen(card, app.buttons["coachDeck.button.done"], in: app)
        XCTAssertTrue(card.frame.contains(stars.frame), "the stars run off the card")
        keepScreenshot(named: "153-coach-message-stars")
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push", "-uitest-noon",
            "-today.cardPage", "0", "-uitest-coach-message", "-uitest-card-folded",
        ]
        app.launch()
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }
        return app
    }

    /// The words on the card, whatever their identifier.
    private func text(_ label: String, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label == %@", label)).firstMatch
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

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
