import XCTest

/// A holiday's takeover on the sample squad: the opening an admin drew plays over everything,
/// its words in the app's language and the squad cheering, then 进场 lifts it and the squad
/// drops onto the home. Screenshots of each are kept for review, at the smallest phone too.
@MainActor
final class OpeningUITests: XCTestCase {
    /// Slow CI simulators can take many seconds to show a screen; a real failure still fails.
    private static let wait: TimeInterval = 30

    func testThanksgivingOpeningThenEnter() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push", "-uitest-noon",
            "-today.cardPage", "0", "-uitest-takeover", "trot", "-opening.played.trot", "never",
        ]
        app.launch()
        // The overlay itself isn't an accessibility element; its words are.
        let title = app.staticTexts["感恩节快乐！"]
        XCTAssertTrue(title.waitForExistence(timeout: Self.wait), "the opening never played")
        Thread.sleep(forTimeInterval: 0.6)
        keepScreenshot(named: "81-opening-thanksgiving-playing")
        let enter = app.buttons["进场"]
        XCTAssertTrue(enter.waitForExistence(timeout: Self.wait), "no 进场 once the opening played")
        XCTAssertTrue(app.staticTexts["— 外卡"].exists, "the letter isn't signed")
        // The button whole on screen, above the home indicator.
        XCTAssertTrue(app.windows.firstMatch.frame.contains(enter.frame), "进场 runs off the screen")
        Thread.sleep(forTimeInterval: 1)
        keepScreenshot(named: "82-opening-thanksgiving-played")

        enter.tap()
        let card = app.descendants(matching: .any).matching(identifier: "today.card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: Self.wait), "今天 never came back after 进场")
        XCTAssertFalse(title.exists, "the opening stayed up after 进场")
        Thread.sleep(forTimeInterval: 2.5)
        keepScreenshot(named: "83-opening-thanksgiving-entered")
    }

    func testChristmasOpeningInEnglish() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(en)", "-AppleLocale", "en", "-uitest-no-push", "-uitest-noon",
            "-today.cardPage", "0", "-uitest-takeover", "jingle", "-opening.played.jingle", "never",
        ]
        app.launch()
        XCTAssertTrue(app.staticTexts["Merry Christmas!"].waitForExistence(timeout: Self.wait), "no title")
        XCTAssertTrue(app.buttons["Enter"].waitForExistence(timeout: Self.wait), "no Enter once it played")
        Thread.sleep(forTimeInterval: 1)
        keepScreenshot(named: "84-opening-christmas-en")
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
