import XCTest

/// A holiday's pre-holiday broadcast in its celebration style, on the sample squad: its card pops
/// up over 今天 with the holiday's header, the member on it, what it gives, 去商店街看看 and 先不了,
/// whole on screen. 先不了 puts it away for good; its button opens 商店街. Screenshots of each are
/// kept for review beside the approved design.
@MainActor
final class BroadcastCelebrationUITests: XCTestCase {
    /// Slow CI simulators can take many seconds to show a screen; a real failure still fails.
    private static let wait: TimeInterval = 30

    func testThanksgivingCardThenNotNow() {
        continueAfterFailure = false
        let app = launch(store: "trot")
        let card = app.descendants(matching: .any).matching(identifier: "broadcast.celebration").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: Self.wait), "the celebration card never popped up")
        XCTAssertTrue(app.staticTexts["感恩节快到了"].exists, "no title on the card")
        XCTAssertTrue(app.staticTexts["商店街上新了，快去看看吧！"].exists, "no line under the title")
        let open = app.buttons["broadcast.celebration.open"]
        let later = app.buttons["broadcast.celebration.later"]
        XCTAssertTrue(open.exists && later.exists, "the card has no 去商店街看看 or 先不了")
        XCTAssertTrue(open.label.contains("去商店街看看"), open.label)
        assertWhole(card, open, later, in: app)
        // The card grows in and the member waves.
        Thread.sleep(forTimeInterval: 1.2)
        keepScreenshot(named: "97-celebration-thanksgiving")
        // Never the banner as well.
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "notice.banner").firstMatch.exists)

        later.tap()
        waitFor(card, "exists == false", "先不了 didn't put the card away", timeout: Self.wait)
        let today = app.descendants(matching: .any).matching(identifier: "today.card").firstMatch
        XCTAssertTrue(today.waitForExistence(timeout: Self.wait), "今天 isn't there under the card")
    }

    func testChristmasCardOpensTheShops() {
        continueAfterFailure = false
        let app = launch(store: "jingle")
        let card = app.descendants(matching: .any).matching(identifier: "broadcast.celebration").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: Self.wait), "the celebration card never popped up")
        XCTAssertTrue(app.staticTexts["圣诞节快到了"].exists, "no title on the card")
        let open = app.buttons["broadcast.celebration.open"]
        assertWhole(card, open, app.buttons["broadcast.celebration.later"], in: app)
        Thread.sleep(forTimeInterval: 1.2)
        keepScreenshot(named: "98-celebration-christmas")

        open.tap()
        let street = app.descendants(matching: .any).matching(identifier: "street.page").firstMatch
        XCTAssertTrue(street.waitForExistence(timeout: Self.wait), "去商店街看看 didn't open 商店街")
        XCTAssertFalse(card.exists, "the card stayed up over 商店街")
    }

    private func launch(store: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push", "-uitest-noon",
            "-today.cardPage", "0", "-uitest-broadcast", store,
        ]
        app.launch()
        return app
    }

    /// The card whole on screen, its buttons inside it.
    private func assertWhole(_ card: XCUIElement, _ open: XCUIElement, _ later: XCUIElement, in app: XCUIApplication) {
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(window.contains(card.frame), "the card runs off the screen: \(card.frame) in \(window)")
        XCTAssertTrue(card.frame.contains(open.frame), "去商店街看看 sticks out of the card: \(open.frame)")
        XCTAssertTrue(card.frame.contains(later.frame), "先不了 sticks out of the card: \(later.frame)")
        XCTAssertLessThan(open.frame.maxY, later.frame.minY + 1, "先不了 isn't under 去商店街看看")
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
