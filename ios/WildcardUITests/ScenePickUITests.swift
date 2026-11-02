import XCTest

/// The scene pick the way the crown winner meets it, on the 战报's last page: the sticker, a
/// scene they know and a carton picked, 「确认」 and the reveal, and the reveal held on the
/// approved design's key moments, so the screenshots sit next to the prototype's frames. CI
/// uploads them (scripts/ios-test.sh).
@MainActor
final class ScenePickUITests: XCTestCase {
    private static let wait: TimeInterval = 30

    func testPickingACartonPlaysTheReveal() {
        let app = launch(language: "zh-Hans")
        openEnding(in: app)
        let confirm = app.buttons["scenePick.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: Self.wait), "no 确认")
        XCTAssertFalse(confirm.isEnabled, "确认 works before a scene is picked")
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
        let save = app.buttons["recap.save"]
        XCTAssertLessThan(confirm.frame.maxY, save.frame.minY, "the sticker runs into 存图")

        XCTAssertTrue(confirm.isEnabled, "确认 doesn't work with a scene picked")
        confirm.tap()
        // The reveal hides the page from VoiceOver as it starts, and ends on the scene by 3 s.
        waitFor(confirm, "exists == false", "the reveal didn't start")
        // Once the scene fills the screen the story is done.
        XCTAssertTrue(app.buttons["recap.entry"].waitForExistence(timeout: Self.wait), "the story didn't close")
        XCTAssertFalse(confirm.exists, "the page came back after the reveal")
    }

    /// Everyone else meets the last page without the sticker.
    func testNoStickerForEveryoneElse() {
        let app = launch(language: "zh-Hans", picker: false)
        openEnding(in: app)
        XCTAssertTrue(app.buttons["recap.save"].waitForExistence(timeout: Self.wait), "no 存图")
        XCTAssertFalse(app.buttons["scenePick.confirm"].exists, "the sticker shows for a reader who doesn't pick")
    }

    func testStickerInEnglish() {
        let app = launch(language: "en")
        openEnding(in: app)
        let pool = app.buttons["scenePick.pool"]
        XCTAssertTrue(pool.waitForExistence(timeout: Self.wait), "no Pool tile")
        pool.tap()
        let line = app.staticTexts["Squad was here 5 wk ago"]
        XCTAssertTrue(line.waitForExistence(timeout: Self.wait), "no last-trained line")
        Thread.sleep(forTimeInterval: 0.4)
        keepScreenshot(named: "54-scenepick-en")
        assertInside(app.windows.firstMatch.frame, [pool, line, app.buttons["scenePick.confirm"]])
    }

    /// A carton opening, held at the prototype's frames: the shake, the flaps flying, the card
    /// rising and filling the screen (covered at 2.8 s).
    func testCartonRevealFrames() {
        for time in [0.6, 1.3, 1.8, 2.4, 2.8] {
            holdReveal(of: "tennis", at: time)
        }
    }

    /// A scene the squad knows has no carton: its card rises straight away.
    func testUsedSceneRevealFrames() {
        for time in [0.4, 0.8] {
            holdReveal(of: "pool", at: time)
        }
    }

    private func holdReveal(of scene: String, at time: Double) {
        let app = launch(language: "zh-Hans", extra: ["-recap-reveal", scene, String(time)])
        // The reveal is hidden from VoiceOver, so there's nothing to wait for but the launch.
        Thread.sleep(forTimeInterval: 1.5)
        // In milliseconds: CI keeps only names without a dot before the extension.
        let millis = String(format: "%04d", Int((time * 1000).rounded()))
        keepScreenshot(named: "56-scenepick-reveal-\(scene)-\(millis)ms")
        app.terminate()
    }

    private func launch(language: String, picker: Bool = true, extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(\(language))", "-AppleLocale", language]
        app.launchArguments +=
            ["-recap", "-uitest-recap-manual", "-uitest-no-push"] + (picker ? ["-recap-picker"] : [])
        app.launchArguments += extra
        app.launch()
        return app
    }

    /// Opens the sample story from its tile and taps through to its last page.
    private func openEnding(in app: XCUIApplication) {
        let tile = app.buttons["recap.entry"]
        XCTAssertTrue(tile.waitForExistence(timeout: Self.wait), "no 战报 tile")
        tile.tap()
        let ending = app.descendants(matching: .any).matching(identifier: "recap.page.ending").firstMatch
        for _ in 0..<12 where !ending.exists {
            XCTAssertTrue(app.buttons["recap.close"].waitForExistence(timeout: Self.wait), "the story didn't open")
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
        }
        XCTAssertTrue(ending.waitForExistence(timeout: Self.wait), "the last page never showed")
        // Let the count settle before the shots.
        Thread.sleep(forTimeInterval: 1.5)
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
