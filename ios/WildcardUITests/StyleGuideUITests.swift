import XCTest

/// Launches the app the way a person does and keeps screenshots for review. CI uploads them
/// (scripts/ios-test.sh).
@MainActor
final class StyleGuideUITests: XCTestCase {
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
            waitForLabel(of: banner(in: app), containing: scene, "the banner didn't switch to \(scene)")
            // Let the color change settle before the shot.
            Thread.sleep(forTimeInterval: 0.6)
            keepScreenshot(named: shot)
        }

        app.buttons["游泳池"].firstMatch.tap()
        let checkIn = app.buttons["styleguide.checkin"]
        XCTAssertEqual(checkIn.label, "打卡")
        checkIn.tap()
        waitForLabel(of: checkIn, containing: "收起", "the check-in button didn't turn into 收起")
        let capsules = [("trained", "练了"), ("fresh", "健康餐"), ("indulgence", "放纵餐"), ("disclaimer", "免责")]
        for (meaning, label) in capsules {
            let capsule = app.buttons["styleguide.capsule.\(meaning)"]
            XCTAssertTrue(capsule.waitForExistence(timeout: 2), "no \(label) capsule")
            XCTAssertEqual(capsule.label, label)
        }
        Thread.sleep(forTimeInterval: 0.8)
        keepScreenshot(named: "06-pool-capsules-open")

        app.buttons["styleguide.capsule.fresh"].tap()
        waitForLabel(of: checkIn, containing: "打卡", "the capsules didn't close")

        app.swipeUp()
        keepScreenshot(named: "07-colors")
        app.swipeUp()
        keepScreenshot(named: "08-type")

        let play = app.buttons["styleguide.motion.play"]
        scrollUntilHittable(play, in: app)
        play.tap()
        waitForLabel(of: play, containing: "回到起点", "the motion demo didn't start")
        // Let the springs settle before the shot.
        Thread.sleep(forTimeInterval: 1.2)
        keepScreenshot(named: "09-motion-finish")
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
        app.launchArguments += ["-AppleLanguages", "(\(language))", "-AppleLocale", language]
        app.launch()
        return app
    }

    /// The squad banner, which VoiceOver reads as one element.
    private func banner(in app: XCUIApplication) -> XCUIElement {
        let banner = app.descendants(matching: .any).matching(identifier: "styleguide.banner").firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 10), "the style guide never appeared")
        return banner
    }

    /// Taps update the UI on the next frames, so a check right after `tap()` can run before
    /// the label changes on a slow simulator. Wait for it instead.
    private func waitForLabel(
        of element: XCUIElement, containing text: String, _ message: String, timeout: TimeInterval = 5
    ) {
        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", text), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [changed], timeout: timeout), .completed, message)
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
