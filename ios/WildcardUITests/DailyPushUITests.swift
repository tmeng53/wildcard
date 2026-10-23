import XCTest

/// The 6pm push's long-press view on the sample squad, through the app's `-daily-push` preview
/// (UI tests can't long-press a real notification): react on a post and watch the author answer,
/// open every emoji, and go first on a day nobody posted. Keeps screenshots for review against
/// the approved design, and checks the view's content stays inside the card on screen.
@MainActor
final class DailyPushUITests: XCTestCase {
    private static let wait: TimeInterval = 30

    func testReactFromThePush() {
        continueAfterFailure = false
        let app = launch(day: "full", language: "zh-Hans")
        let react = app.buttons.matching(identifier: "dailyPush.react").firstMatch
        XCTAssertTrue(react.waitForExistence(timeout: Self.wait), "no post to react to")
        settle()
        let posts = app.descendants(matching: .any).matching(identifier: "dailyPush.post")
        XCTAssertEqual(posts.count, 4, "the push should show four posts")
        assertOnScreen(posts.element(boundBy: 0), in: app)
        keepScreenshot(named: "60-push-react")
        // On a small phone the rest scroll into view, 「还有 2 条」 last.
        app.swipeUp()
        settle()
        assertOnScreen(posts.element(boundBy: 3), in: app)
        assertOnScreen(app.buttons["dailyPush.more"], in: app)
        keepScreenshot(named: "60-push-react-end")
        app.swipeDown()
        settle()

        react.tap()
        let bar = app.descendants(matching: .any).matching(identifier: "dailyPush.emojiBar").firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: Self.wait), "the emoji bar didn't open")
        assertOnScreen(bar, in: app)
        settle()
        keepScreenshot(named: "61-push-react-bar")

        // The emoji flies to the author, pops over them, and their character plays its move.
        app.buttons["dailyPush.emoji.💪"].tap()
        for frame in 0..<8 {
            keepScreenshot(named: String(format: "62-push-react-reacted-%02d", frame))
            Thread.sleep(forTimeInterval: 0.2)
        }
        waitFor(bar, "exists == false", "the emoji bar stayed open")
        XCTAssertEqual(react.label, "我的回应 💪，换一个", "my emoji isn't on my button")

        // ＋ lays every emoji over the push, since a push has no keyboard.
        react.tap()
        XCTAssertTrue(bar.waitForExistence(timeout: Self.wait))
        app.buttons["更多表情"].tap()
        settle()
        keepScreenshot(named: "63-push-react-all")

        app.buttons["dailyPush.emoji.🔥"].tap()
        waitFor(react, "label == '我的回应 🔥，换一个'", "picking from every emoji didn't react")

        app.buttons["dailyPush.more"].tap()
        waitFor(app.staticTexts["dailyPush.opened"], "label == 'feed'", "「还有 2 条」 didn't open 动态")
    }

    func testNobodyPostedYet() {
        continueAfterFailure = false
        let app = launch(day: "empty", language: "zh-Hans")
        let checkIn = app.buttons["dailyPush.checkIn"]
        XCTAssertTrue(checkIn.waitForExistence(timeout: Self.wait), "no 我去发一个")
        settle()
        assertOnScreen(checkIn, in: app)
        keepScreenshot(named: "64-push-react-empty")
        checkIn.tap()
        waitFor(app.staticTexts["dailyPush.opened"], "label == 'checkIn'", "我去发一个 didn't open 打卡")
    }

    func testPushInEnglish() {
        continueAfterFailure = false
        let app = launch(day: "full", language: "en")
        XCTAssertTrue(
            app.buttons.matching(identifier: "dailyPush.react").firstMatch.waitForExistence(timeout: Self.wait))
        settle()
        keepScreenshot(named: "65-push-react-en")
    }

    private func launch(day: String, language: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(\(language))", "-AppleLocale", language, "-uitest-no-push", "-uitest-noon",
            "-daily-push", day,
        ]
        app.launch()
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }
        return app
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
