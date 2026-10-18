import XCTest

/// Launches the app the way a person does and keeps screenshots for review. CI uploads them
/// (scripts/ios-test.sh).
@MainActor
final class StyleGuideUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testStyleGuideInChinese() {
        let app = launch(language: "zh-Hans")
        XCTAssertTrue(header(in: app).label.contains("小队本周打卡"))
        XCTAssertTrue(app.staticTexts["跑道红"].exists)
        keepScreenshot(named: "01-style-guide-zh-top")

        app.swipeUp()
        keepScreenshot(named: "02-style-guide-zh-type")

        let play = app.buttons["styleguide.motion.play"]
        scrollUntilHittable(play, in: app)
        keepScreenshot(named: "03-style-guide-zh-motion-start")
        play.tap()
        XCTAssertEqual(play.label, "回到起点")
        // Let the springs settle before the shot.
        Thread.sleep(forTimeInterval: 1.2)
        keepScreenshot(named: "04-style-guide-zh-motion-finish")
    }

    func testStyleGuideInEnglish() {
        let app = launch(language: "en")
        XCTAssertTrue(header(in: app).label.contains("Squad check-ins this week"))
        XCTAssertTrue(app.staticTexts["Track red"].exists)
        keepScreenshot(named: "05-style-guide-en-top")
    }

    private func launch(language: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(\(language))", "-AppleLocale", language]
        app.launch()
        return app
    }

    /// The score header, which VoiceOver reads as one element.
    private func header(in app: XCUIApplication) -> XCUIElement {
        let header = app.descendants(matching: .any).matching(identifier: "styleguide.header").firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 10), "the style guide never appeared")
        return header
    }

    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 where !element.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable, "\(element) never scrolled into view")
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
