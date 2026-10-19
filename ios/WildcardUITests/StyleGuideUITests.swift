import XCTest

/// Launches the app the way a person does and keeps screenshots for review. CI uploads them
/// (scripts/ios-test.sh).
@MainActor
final class StyleGuideUITests: XCTestCase {
    /// How long a check waits for the UI. On a busy CI runner one accessibility query can take
    /// several seconds, so a 5s wait gets one or two looks before it times out; a wait that
    /// succeeds returns as soon as it does, so a generous limit only slows a real failure.
    private static let wait: TimeInterval = 30

    /// Every scene recolors the style guide; the check-in opens into its four capsules.
    func testStyleGuideInChinese() {
        let app = launch(language: "zh-Hans")
        XCTAssertTrue(banner(in: app).label.contains("周三不练腿俱乐部"))
        XCTAssertTrue(banner(in: app).label.contains("游泳池"))
        keepScreenshot(named: "01-scene-pool")

        let scenes = [
            ("跑道", "02-scene-track"), ("健身房", "03-scene-gym"), ("网球场", "04-scene-tennis"),
            ("攀岩馆", "05-scene-climbing"),
        ]
        for (scene, shot) in scenes {
            app.buttons[scene].firstMatch.tap()
            waitForLabel(of: banner(in: app), "label CONTAINS %@", scene, "the banner didn't switch to \(scene)")
            // Let the color change settle before the shot.
            Thread.sleep(forTimeInterval: 0.6)
            keepScreenshot(named: shot)
        }

        app.buttons["游泳池"].firstMatch.tap()
        waitForLabel(of: banner(in: app), "label CONTAINS %@", "游泳池", "the banner didn't switch back to 游泳池")
        let checkIn = app.buttons["styleguide.checkin"]
        XCTAssertEqual(checkIn.label, "打卡")
        checkIn.tap()
        waitForLabel(of: checkIn, "label == %@", "收起", "the check-in button didn't turn into 收起")
        let capsules = [("trained", "练了"), ("healthyMeal", "健康餐"), ("cheatMeal", "放纵餐"), ("disclaimer", "请假")]
        for (meaning, label) in capsules {
            let capsule = app.buttons["styleguide.capsule.\(meaning)"]
            XCTAssertTrue(capsule.waitForExistence(timeout: Self.wait), "no \(label) capsule")
            XCTAssertEqual(capsule.label, label)
        }
        Thread.sleep(forTimeInterval: 0.8)
        keepScreenshot(named: "06-pool-capsules-open")

        app.buttons["styleguide.capsule.healthyMeal"].tap()
        waitForLabel(of: checkIn, "label == %@", "打卡", "the capsules didn't close")

        app.swipeUp()
        keepScreenshot(named: "07-colors")
        app.swipeUp()
        keepScreenshot(named: "08-type")

        let play = app.buttons["styleguide.motion.play"]
        scrollUntilHittable(play, in: app)
        play.tap()
        waitForLabel(of: play, "label == %@", "回到起点", "the motion demo didn't start")
        // Let the springs settle before the shot.
        Thread.sleep(forTimeInterval: 1.2)
        keepScreenshot(named: "09-motion-finish")

    }

    /// The sport picker demo starts with 跑步 picked, so 完成 counts 1; picking 快走 makes it 2.
    func testSportPickerDemo() {
        let app = launch(language: "zh-Hans")
        _ = banner(in: app)
        let done = app.buttons["styleguide.picker.done"]
        scrollUntilHittable(done, in: app)
        app.swipeUp()
        XCTAssertTrue(app.buttons["styleguide.picker.pill.run"].isSelected, "跑步 isn't picked to start")
        let walk = app.buttons["styleguide.picker.tile.walk"]
        XCTAssertTrue(walk.waitForExistence(timeout: Self.wait), "no 快走 tile")
        XCTAssertFalse(walk.isSelected)
        XCTAssertTrue(app.buttons["styleguide.picker.category.runWalk"].isSelected)
        Thread.sleep(forTimeInterval: 0.6)
        keepScreenshot(named: "11-picker")

        walk.tap()
        waitForLabel(of: done, "label CONTAINS %@", "2", "picking 快走 didn't bump 完成 to 2")
        XCTAssertTrue(walk.isSelected, "the 快走 tile isn't marked selected")
        // Let the check badge spring in before the shot.
        Thread.sleep(forTimeInterval: 0.6)
        keepScreenshot(named: "12-picker-selected")
    }

    func testStyleGuideInEnglish() {
        let app = launch(language: "en")
        XCTAssertTrue(banner(in: app).label.contains("Skip Leg Day Club"))
        XCTAssertEqual(app.buttons["styleguide.checkin"].label, "Check in")
        XCTAssertEqual(app.buttons["styleguide.tab.highlights"].label, "Highlights")
        keepScreenshot(named: "10-en-top")
    }

    private func launch(language: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-styleguide", "-AppleLanguages", "(\(language))", "-AppleLocale", language]
        app.launch()
        return app
    }

    /// The squad banner, which VoiceOver reads as one element.
    private func banner(in app: XCUIApplication) -> XCUIElement {
        let banner = app.descendants(matching: .any).matching(identifier: "styleguide.banner").firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: Self.wait), "the style guide never appeared")
        return banner
    }

    /// Taps update the UI on the next frames, so a check right after `tap()` can run before
    /// the label changes on a slow simulator. Wait for it instead, as strictly as the check was:
    /// `label == %@` for an exact label, `label CONTAINS %@` for the banner's combined label.
    private func waitForLabel(
        of element: XCUIElement, _ format: String, _ text: String, _ message: String,
        timeout: TimeInterval = StyleGuideUITests.wait
    ) {
        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: format, text), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [changed], timeout: timeout), .completed, message)
    }

    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 where !element.isHittable {
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
