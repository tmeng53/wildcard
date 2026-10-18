import XCTest

/// Checks in from 今天 the way a person does, and keeps screenshots for review. Photos come
/// from `-uitest-photos`, since UI tests can't drive the system photo picker reliably.
@MainActor
final class TodayUITests: XCTestCase {
    /// 练了 with three photos: pick a cover, write a caption, post, and land back on the scene
    /// with the squad bar ticked up. Afterwards 免责 is greyed out for the day.
    func testTrainedCheckIn() {
        let app = launch(language: "zh-Hans", photos: 3)
        let card = topCard(in: app)
        XCTAssertTrue(card.label.contains("周三不练腿俱乐部"))
        XCTAssertTrue(card.label.contains("14/22"))
        XCTAssertTrue(card.label.contains("今天 3 人练了"))
        settle()
        keepScreenshot(named: "13-today")

        let checkIn = app.buttons["today.checkin"]
        XCTAssertEqual(checkIn.label, "打卡")
        checkIn.tap()
        waitForLabel(of: checkIn, "label == %@", "收起", "the check-in button didn't turn into 收起")
        for (meaning, label) in [("trained", "练了"), ("fresh", "健康餐"), ("indulgence", "放纵餐"), ("disclaimer", "免责")] {
            let capsule = app.buttons["today.capsule.\(meaning)"]
            XCTAssertTrue(capsule.waitForExistence(timeout: 2), "no \(label) capsule")
            XCTAssertEqual(capsule.label, label)
        }
        settle()
        keepScreenshot(named: "14-today-burst")

        app.buttons["today.capsule.trained"].tap()
        let post = app.buttons["compose.post"]
        XCTAssertTrue(post.waitForExistence(timeout: 3), "the compose page never opened")
        XCTAssertTrue(app.buttons["compose.sport.run"].isSelected, "the last sport used (跑步) isn't picked")
        app.buttons["compose.photo.2"].tap()
        let caption = app.descendants(matching: .any).matching(identifier: "compose.caption").firstMatch
        caption.tap()
        caption.typeText("晨跑 5 公里，腿还在")
        settle()
        keepScreenshot(named: "15-compose-trained")

        post.tap()
        let bubble = app.descendants(matching: .any).matching(identifier: "today.bubble").firstMatch
        XCTAssertTrue(bubble.waitForExistence(timeout: 5), "no payoff bubble after posting")
        XCTAssertTrue(bubble.label.contains("晨跑 5 公里，腿还在"))
        waitForLabel(of: card, "label CONTAINS %@", "15/22", "the squad bar didn't tick up to 15/22")
        XCTAssertTrue(card.label.contains("今天 4 人练了"))
        // Let the cheer play out before the shot.
        Thread.sleep(forTimeInterval: 1.2)
        keepScreenshot(named: "16-today-trained-payoff")

        checkIn.tap()
        let disclaimer = app.buttons["today.capsule.disclaimer"]
        XCTAssertTrue(disclaimer.waitForExistence(timeout: 2))
        disclaimer.tap()
        XCTAssertFalse(app.buttons["disclaimer.post"].waitForExistence(timeout: 1), "免责 opened after training")
        settle()
        keepScreenshot(named: "17-today-disclaimer-unavailable")
    }

    /// 免责: write a reason, ask for drafts, roll the dice, post, and the line lands on the scene
    /// without moving the squad bar.
    func testDisclaimer() {
        let app = launch(language: "zh-Hans", photos: 0)
        let card = topCard(in: app)
        app.buttons["today.checkin"].tap()
        let capsule = app.buttons["today.capsule.disclaimer"]
        XCTAssertTrue(capsule.waitForExistence(timeout: 2))
        capsule.tap()

        let field = app.descendants(matching: .any).matching(identifier: "disclaimer.field").firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3), "the 免责声明 card never opened")
        field.tap()
        field.typeText("加班")
        app.buttons["disclaimer.write"].tap()
        let first = app.buttons["disclaimer.draft.1"]
        XCTAssertTrue(first.waitForExistence(timeout: 3), "帮我写 gave no drafts")
        XCTAssertTrue(app.buttons["disclaimer.draft.3"].exists, "帮我写 gave fewer than 3 drafts")
        first.tap()
        settle()
        keepScreenshot(named: "18-disclaimer-drafts")

        app.buttons["disclaimer.dice"].tap()
        XCTAssertFalse(app.buttons["disclaimer.draft.1"].exists, "the dice kept the old drafts")
        let line = field.value as? String ?? ""
        XCTAssertFalse(line.isEmpty, "the dice left the field empty")
        app.buttons["disclaimer.post"].tap()

        let bubble = app.descendants(matching: .any).matching(identifier: "today.bubble").firstMatch
        XCTAssertTrue(bubble.waitForExistence(timeout: 5), "no payoff bubble after the 免责声明")
        XCTAssertTrue(bubble.label.contains(line))
        XCTAssertTrue(card.label.contains("14/22"), "a 免责声明 moved the squad bar")
        settle()
        keepScreenshot(named: "19-today-disclaimer-posted")
    }

    func testTodayInEnglish() {
        let app = launch(language: "en", photos: 0)
        XCTAssertTrue(topCard(in: app).label.contains("Skip Leg Day Club"))
        XCTAssertEqual(app.buttons["today.checkin"].label, "Check in")
        settle()
        keepScreenshot(named: "20-today-en")
    }

    private func launch(language: String, photos: Int) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-uitest-photos", "\(photos)", "-AppleLanguages", "(\(language))", "-AppleLocale", language,
        ]
        app.launch()
        return app
    }

    /// The top card, which VoiceOver reads as one element.
    private func topCard(in app: XCUIApplication) -> XCUIElement {
        let card = app.descendants(matching: .any).matching(identifier: "today.card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "今天 never appeared")
        return card
    }

    /// Lets springs and blurs settle before a screenshot.
    private func settle() {
        Thread.sleep(forTimeInterval: 0.8)
    }

    /// Taps update the UI on the next frames; wait for the label instead of checking at once.
    private func waitForLabel(
        of element: XCUIElement, _ format: String, _ text: String, _ message: String,
        timeout: TimeInterval = 5
    ) {
        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: format, text), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [changed], timeout: timeout), .completed, message)
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
