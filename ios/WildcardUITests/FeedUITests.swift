import XCTest

/// 动态 on the sample squad, the way a teammate uses it: react with an emoji from the bar, the
/// grid or by holding the card, watch it fly to the author's character, see who reacted, and
/// keep screenshots for review. Each check that the
/// content clears the floating tab bar runs where the screen has the most in it.
@MainActor
final class FeedUITests: XCTestCase {
    private static let wait: TimeInterval = 30
    /// More than the sample squad's posts need to reach the end.
    private static let maxSwipes = 12

    func testReact() {
        continueAfterFailure = false
        let app = launch(language: "zh-Hans")
        let react = app.buttons.matching(identifier: "feed.react").firstMatch
        XCTAssertTrue(react.waitForExistence(timeout: Self.wait), "no post to react to")
        settle()
        assertClearOfTheTabBar(app.staticTexts["feed.title"], in: app)
        keepScreenshot(named: "40-feed")

        react.tap()
        let bar = app.buttons["feed.emoji.💪"]
        XCTAssertTrue(bar.waitForExistence(timeout: Self.wait), "the emoji bar didn't open")
        assertOnScreen(bar, in: app)
        settle()
        keepScreenshot(named: "41-feed-emoji-bar")

        // The emoji flies to the author's head and the character plays its move.
        bar.tap()
        for frame in 0..<12 {
            keepScreenshot(named: String(format: "42-feed-reacted-%02d", frame))
            Thread.sleep(forTimeInterval: 0.12)
        }
        waitFor(bar, "exists == false", "the emoji bar stayed open")
        XCTAssertEqual(react.label, "我的回应：💪", "my emoji isn't on my button")

        // Tapping the heads opens who reacted, right at the row.
        app.buttons.matching(identifier: "feed.reactions").firstMatch.tap()
        let who = app.descendants(matching: .any).matching(identifier: "feed.who").firstMatch
        XCTAssertTrue(who.waitForExistence(timeout: Self.wait), "who reacted didn't open")
        assertOnScreen(who, in: app)
        settle()
        keepScreenshot(named: "43-feed-who-reacted")
        app.staticTexts["feed.title"].tap()
        waitFor(who, "exists == false", "who reacted stayed open")

        // The oldest posts scroll up clear of the tab bar: swipe until the last post is on
        // screen, as the list builds its cards as they come.
        let posts = app.descendants(matching: .any).matching(identifier: "feed.post")
        let tabBarTop = app.buttons["tab.feed"].frame.minY
        var swipes = 0
        let feed = app.scrollViews.firstMatch
        while swipes < Self.maxSwipes, posts.element(boundBy: posts.count - 1).frame.maxY > tabBarTop {
            feed.swipeUp()
            swipes += 1
        }
        settle()
        // Kept before the check, so a failure shows where the list stopped.
        keepScreenshot(named: "45-feed-end")
        assertClearOfTheTabBar(posts.element(boundBy: posts.count - 1), in: app)
    }

    /// A 练了 with its minutes shows them as the card's big number. The newest posts on top are a
    /// salad and a 请假条, so the run's card is scrolled to, a little at a time.
    func testMinutes() {
        continueAfterFailure = false
        let app = launch(language: "zh-Hans")
        XCTAssertTrue(app.staticTexts["feed.title"].waitForExistence(timeout: Self.wait), "no 动态")
        let minutes = app.descendants(matching: .any).matching(identifier: "feed.minutes").firstMatch
        let tabBarTop = app.buttons["tab.feed"].frame.minY
        let feed = app.scrollViews.firstMatch
        var drags = 0
        while drags < Self.maxSwipes, !(minutes.exists && minutes.frame.maxY <= tabBarTop) {
            let from = feed.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -240)))
            drags += 1
        }
        XCTAssertTrue(minutes.exists, "no minutes on a 练了")
        settle()
        // Kept before the check, so a failure shows where the list stopped.
        keepScreenshot(named: "44-feed-minutes")
        assertClearOfTheTabBar(minutes, in: app)
    }

    /// ＋ opens our own emoji grid, and holding a card then sliding along the bar picks.
    func testGridAndHoldToPick() {
        continueAfterFailure = false
        let app = launch(language: "zh-Hans")
        let react = app.buttons.matching(identifier: "feed.react").firstMatch
        XCTAssertTrue(react.waitForExistence(timeout: Self.wait), "no post to react to")
        settle()
        react.tap()
        let bar = app.buttons["feed.emoji.💪"]
        XCTAssertTrue(bar.waitForExistence(timeout: Self.wait), "the emoji bar didn't open")

        // ＋ opens our own emoji grid in place of the bar.
        app.buttons["feed.emoji.more"].tap()
        let grid = app.descendants(matching: .any).matching(identifier: "feed.emojiGrid").firstMatch
        XCTAssertTrue(grid.waitForExistence(timeout: Self.wait), "the emoji grid didn't open")
        assertOnScreen(grid, in: app)
        settle()
        keepScreenshot(named: "41-feed-emoji-grid")
        // 全部, as the grid opens on 最近 once this phone has picked before.
        grid.buttons["全部"].firstMatch.tap()
        grid.buttons["😀"].firstMatch.tap()
        waitFor(react, "label == '我的回应：😀'", "picking from the grid didn't react")

        // Holding the card and sliding to 😂 swaps it: the bar's slots sit left of my button's
        // right edge, 44 points each.
        let slot = react.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0)).withOffset(
            CGVector(dx: -(7 - 2.5) * 44 - 4, dy: -8 - 26))
        // Pressed on the card's words, above its row.
        let words = react.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0)).withOffset(
            CGVector(dx: -120, dy: -50))
        words.press(forDuration: 0.8, thenDragTo: slot)
        waitFor(react, "label == '我的回应：😂'", "holding and sliding didn't pick 😂")
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
