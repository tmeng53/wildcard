import XCTest

/// The scene pick the way the crown winner meets it: the sticker, a scene they know and a
/// carton picked, 「就它了」 and the reveal, and the reveal held on the approved design's key
/// moments, so the screenshots sit next to the prototype's frames. CI uploads them
/// (scripts/ios-test.sh).
@MainActor
final class ScenePickUITests: XCTestCase {
    private static let wait: TimeInterval = 30

    func testPickingACartonPlaysTheReveal() {
        let app = launch(language: "zh-Hans")
        let confirm = app.buttons["scenePick.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: Self.wait), "no 就它了")
        XCTAssertFalse(confirm.isEnabled, "就它了 works before a scene is picked")
        keepScreenshot(named: "50-scenepick-sticker")

        let pool = app.buttons["scenePick.pool"]
        pool.tap()
        waitFor(pool, "isSelected == true", "tapping 泳池 didn't pick it")
        XCTAssertTrue(app.staticTexts["小队 5 周前在这里练过"].waitForExistence(timeout: Self.wait), "no last-trained line")
        Thread.sleep(forTimeInterval: 0.4)
        keepScreenshot(named: "51-scenepick-pool-picked")

        let tennis = app.buttons["scenePick.tennis"]
        tennis.tap()
        waitFor(tennis, "isSelected == true", "tapping the tennis carton didn't pick it")
        XCTAssertEqual(tennis.label, "网球场，还没开过")
        XCTAssertTrue(app.staticTexts["小队还没来过"].waitForExistence(timeout: Self.wait), "no 小队还没来过")
        // Mid-wiggle: the shake runs over the first 0.2 s after the pick.
        Thread.sleep(forTimeInterval: 0.05)
        keepScreenshot(named: "52-scenepick-carton-picked")
        assertInside(app.windows.firstMatch.frame, [pool, tennis, confirm, app.staticTexts["小队还没来过"]])

        XCTAssertTrue(confirm.isEnabled, "就它了 doesn't work with a scene picked")
        confirm.tap()
        // The reveal hides the page from VoiceOver as it starts, and ends on the scene by 3 s.
        waitFor(confirm, "exists == false", "the reveal didn't start")
        Thread.sleep(forTimeInterval: 3.5)
        keepScreenshot(named: "53-scenepick-landed")
    }

    func testStickerInEnglish() {
        let app = launch(language: "en")
        let pool = app.buttons["scenePick.pool"]
        XCTAssertTrue(pool.waitForExistence(timeout: Self.wait), "no Pool tile")
        pool.tap()
        let line = app.staticTexts["Squad was here 5 wk ago"]
        XCTAssertTrue(line.waitForExistence(timeout: Self.wait), "no last-trained line")
        Thread.sleep(forTimeInterval: 0.4)
        keepScreenshot(named: "54-scenepick-en")
        assertInside(app.windows.firstMatch.frame, [pool, line, app.buttons["scenePick.confirm"]])
    }

    /// Eight teammates: the squad walks through in a queue under the sticker.
    func testEightWalkThrough() {
        let app = launch(language: "zh-Hans", extra: ["-scene-pick-members", "8"])
        XCTAssertTrue(app.buttons["scenePick.confirm"].waitForExistence(timeout: Self.wait), "no 就它了")
        keepScreenshot(named: "55-scenepick-eight")
    }

    /// A carton opening, held at the prototype's frames: the shake, the flaps flying, the card
    /// rising and filling the screen.
    func testCartonRevealFrames() {
        for time in ["0.6", "1.3", "1.8", "2.4"] {
            holdReveal(of: "tennis", at: time)
        }
    }

    /// A scene the squad knows has no carton: its card rises straight away.
    func testUsedSceneRevealFrames() {
        for time in ["0.4", "0.8"] {
            holdReveal(of: "pool", at: time)
        }
    }

    private func holdReveal(of scene: String, at time: String) {
        let app = launch(language: "zh-Hans", extra: ["-scene-pick-reveal", scene, time])
        // The reveal is hidden from VoiceOver, so there's nothing to wait for but the launch.
        Thread.sleep(forTimeInterval: 1.5)
        keepScreenshot(named: "56-scenepick-reveal-\(scene)-\(time)s")
        app.terminate()
    }

    private func launch(language: String, extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-scene-pick", "-AppleLanguages", "(\(language))", "-AppleLocale", language] + extra
        app.launch()
        return app
    }

    private func assertInside(_ screen: CGRect, _ elements: [XCUIElement]) {
        for element in elements {
            XCTAssertTrue(screen.contains(element.frame), "\(element) is cut off: \(element.frame) on \(screen)")
        }
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
