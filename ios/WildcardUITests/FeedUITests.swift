import XCTest

/// 动态 on the sample squad, the way a teammate uses it: react with an emoji, watch the author's
/// character answer, and keep screenshots for review. Each check that the
/// content clears the floating tab bar runs where the screen has the most in it.
@MainActor
final class FeedUITests: XCTestCase {
    private static let wait: TimeInterval = 30

    func testReact() {
        continueAfterFailure = false
        let app = launch(language: "zh-Hans")
        let react = app.buttons.matching(identifier: "feed.react").firstMatch
        XCTAssertTrue(react.waitForExistence(timeout: Self.wait), "no post to react to")
        settle()
        assertClearOfTheTabBar(app.staticTexts["feed.title"], in: app)
        keepScreenshot(named: "40-feed")

        react.tap()
        settle()
        keepScreenshot(named: "41-feed-tapped")
        let bar = app.descendants(matching: .any).matching(identifier: "feed.emojiBar").firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: Self.wait), "the emoji bar didn't open")
        assertOnScreen(bar, in: app)
        settle()
        keepScreenshot(named: "41-feed-emoji-bar")

        // The emoji pops on the card and the author's character plays its move.
        app.buttons["feed.emoji.💪"].tap()
        for frame in 0..<10 {
            keepScreenshot(named: String(format: "42-feed-reacted-%02d", frame))
            Thread.sleep(forTimeInterval: 0.15)
        }
        waitFor(bar, "exists == false", "the emoji bar stayed open")
        XCTAssertEqual(react.label, "我的回应：💪", "my emoji isn't on my button")

        // Tapping the faces lists who left what.
        app.buttons.matching(identifier: "feed.reactions").firstMatch.tap()
        settle()
        keepScreenshot(named: "43-feed-who-reacted")

        // The oldest posts scroll up clear of the tab bar.
        app.swipeUp()
        app.swipeUp()
        app.swipeUp()
        settle()
        let posts = app.descendants(matching: .any).matching(identifier: "feed.post")
        let last = posts.element(boundBy: posts.count - 1)
        assertClearOfTheTabBar(last, in: app)
        keepScreenshot(named: "45-feed-end")
    }

    func testFeedInEnglish() {
        continueAfterFailure = false
        let app = launch(language: "en")
        XCTAssertTrue(app.staticTexts["feed.title"].waitForExistence(timeout: Self.wait))
        XCTAssertEqual(app.staticTexts["feed.title"].label, "Feed")
        settle()
        keepScreenshot(named: "46-feed-en")
    }

    /// No posts yet: the squad's scene with me in it, and 去打卡 takes me to 今天.
    func testEmptyFeed() {
        continueAfterFailure = false
        let app = launch(language: "zh-Hans", extra: ["-uitest-empty-feed"])
        let checkIn = app.buttons["feed.checkIn"]
        XCTAssertTrue(checkIn.waitForExistence(timeout: Self.wait), "no empty feed")
        settle()
        assertClearOfTheTabBar(checkIn, in: app)
        keepScreenshot(named: "47-feed-empty")
        checkIn.tap()
        waitFor(app.buttons["tab.today"], "isSelected == true", "去打卡 didn't open 今天")
    }

    private func launch(language: String, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments +=
            [
                "-AppleLanguages", "(\(language))", "-AppleLocale", language, "-uitest-no-push", "-uitest-noon", "-tab",
                "feed",
            ] + extra
        app.launch()
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }
        return app
    }

    /// Fully on screen and above the floating tab bar, so nothing covers it.
    private func assertClearOfTheTabBar(_ element: XCUIElement, in app: XCUIApplication) {
        assertOnScreen(element, in: app)
        let bar = app.buttons["tab.feed"]
        XCTAssertTrue(bar.exists, "no tab bar")
        XCTAssertLessThanOrEqual(element.frame.maxY, bar.frame.minY, "\(element.identifier) is under the tab bar")
    }

    private func assertOnScreen(_ element: XCUIElement, in app: XCUIApplication) {
        let screen = app.windows.firstMatch.frame
        XCTAssertTrue(screen.contains(element.frame), "\(element.identifier) is cut off: \(element.frame)")
    }

    /// Lets springs settle before a screenshot.
    private func settle() {
        Thread.sleep(forTimeInterval: 0.8)
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
