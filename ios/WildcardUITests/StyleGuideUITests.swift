import XCTest

/// Launches the style guide the way a person does and keeps screenshots of every section for
/// review. CI uploads them (scripts/ios-test.sh).
@MainActor
final class StyleGuideUITests: XCTestCase {
    /// How long a check waits for the UI. On a busy CI runner one accessibility query can take
    /// several seconds, so a 5s wait gets one or two looks before it times out; a wait that
    /// succeeds returns as soon as it does, so a generous limit only slows a real failure.
    private static let wait: TimeInterval = 30

    private static let scenes = ["pool", "track", "gym", "tennis", "climbing"]

    /// Every scene recolors the accent: the colors section in each one.
    func testScenes() {
        let app = launch(language: "zh-Hans")
        XCTAssertTrue(section(1, in: app).label.contains("颜色"))
        for (index, scene) in Self.scenes.enumerated() {
            pick(scene: scene, in: app)
            keepScreenshot(named: String(format: "%02d-colors-%@", index + 1, scene))
        }
    }

    /// Type, layout, buttons and picks in the pool scene.
    func testSectionsInPool() {
        let app = launch(language: "zh-Hans")
        _ = section(1, in: app)

        scrollUntilHittable(section(2, in: app), in: app)
        keepScreenshot(named: "10-type")
        scrollUntilHittable(section(3, in: app), in: app)
        keepScreenshot(named: "11-layout")

        let steps = app.descendants(matching: .any).matching(identifier: "styleguide.stepheader").firstMatch
        scrollUntilHittable(steps, in: app)
        keepScreenshot(named: "12-buttons")

        let swim = app.buttons["styleguide.pick.swim"]
        let run = app.buttons["styleguide.pick.run"]
        scrollUntilHittable(run, in: app)
        XCTAssertTrue(swim.isSelected, "游泳 isn't picked to start")
        XCTAssertFalse(run.isSelected, "跑步 is picked to start")
        run.tap()
        waitFor(run, "isSelected == true", "tapping 跑步 didn't pick it")
        // Let the check badge spring in before the shot.
        Thread.sleep(forTimeInterval: 0.6)
        keepScreenshot(named: "13-picks")

    }

    /// The check-in kinds, the capsules opening, and my status ring closing.
    func testKindsAndStatusInPool() {
        let app = launch(language: "zh-Hans")
        _ = section(1, in: app)
        let checkIn = app.buttons["styleguide.checkin"]
        scrollUntilHittable(checkIn, in: app)
        XCTAssertEqual(checkIn.label, "打卡")
        keepScreenshot(named: "14-kinds")
        checkIn.tap()
        waitFor(checkIn, "label == '收起'", "the check-in button didn't turn into 收起")
        let capsules = [("trained", "练了"), ("healthyMeal", "健康餐"), ("cheatMeal", "放纵餐"), ("disclaimer", "请假")]
        for (kind, label) in capsules {
            let capsule = app.buttons["styleguide.capsule.\(kind)"]
            XCTAssertTrue(capsule.waitForExistence(timeout: Self.wait), "no \(label) capsule")
            XCTAssertEqual(capsule.label, label)
        }
        Thread.sleep(forTimeInterval: 0.8)
        keepScreenshot(named: "15-capsules-open")
        app.buttons["styleguide.capsule.healthyMeal"].tap()
        waitFor(checkIn, "label == '打卡'", "the capsules didn't close")

        let mine = app.descendants(matching: .any).matching(identifier: "styleguide.ring.mine").firstMatch
        let play = app.buttons["styleguide.ring.play"]
        scrollUntilHittable(play, in: app)
        XCTAssertEqual(mine.value as? String, "还没打卡")
        keepScreenshot(named: "16-status")
        play.tap()
        waitFor(mine, "value == '打卡了'", "my ring didn't close")
        // Let the ring draw and the avatar pop before the shot.
        Thread.sleep(forTimeInterval: 1.2)
        keepScreenshot(named: "17-status-checked-in")
    }

    /// The list, the character's stage and the motion springs.
    func testListStageAndMotionInPool() {
        let app = launch(language: "zh-Hans")
        _ = section(1, in: app)

        scrollUntilHittable(section(8, in: app), in: app)
        keepScreenshot(named: "18-list")
        scrollUntilHittable(section(9, in: app), in: app)
        app.swipeUp()
        keepScreenshot(named: "19-stage")

        let motion = app.buttons["styleguide.motion.play"]
        scrollUntilHittable(motion, in: app)
        motion.tap()
        waitFor(motion, "label == '回到起点'", "the motion demo didn't start")
        // Let the springs settle before the shot.
        Thread.sleep(forTimeInterval: 1.2)
        keepScreenshot(named: "20-motion")
    }

    /// The gym is the one dark scene: graphite accent, volt on it.
    func testComponentsInGym() {
        let app = launch(language: "zh-Hans")
        pick(scene: "gym", in: app)
        let steps = app.descendants(matching: .any).matching(identifier: "styleguide.stepheader").firstMatch
        scrollUntilHittable(steps, in: app)
        keepScreenshot(named: "21-gym-buttons")
        scrollUntilHittable(app.buttons["styleguide.pick.run"], in: app)
        keepScreenshot(named: "22-gym-picks")
        scrollUntilHittable(app.buttons["styleguide.checkin"], in: app)
        keepScreenshot(named: "23-gym-kinds")
        scrollUntilHittable(app.buttons["styleguide.ring.play"], in: app)
        keepScreenshot(named: "24-gym-status")
    }

    func testStyleGuideInEnglish() {
        let app = launch(language: "en")
        XCTAssertTrue(section(1, in: app).label.contains("Color"))
        XCTAssertEqual(app.buttons["styleguide.scene.pool"].label, "Pool")
        let checkIn = app.buttons["styleguide.checkin"]
        scrollUntilHittable(checkIn, in: app)
        XCTAssertEqual(checkIn.label, "Check in")
        keepScreenshot(named: "25-en-kinds")
    }

    private func launch(language: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-styleguide", "-AppleLanguages", "(\(language))", "-AppleLocale", language]
        app.launch()
        return app
    }

    /// A section's title, which VoiceOver reads as one header.
    private func section(_ number: Int, in app: XCUIApplication) -> XCUIElement {
        let title = app.descendants(matching: .any).matching(identifier: "styleguide.section.\(number)").firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: Self.wait), "section \(number) never appeared")
        return title
    }

    private func pick(scene: String, in app: XCUIApplication) {
        let item = app.buttons["styleguide.scene.\(scene)"]
        XCTAssertTrue(item.waitForExistence(timeout: Self.wait), "no \(scene) in the scene bar")
        item.tap()
        waitFor(item, "isSelected == true", "the style guide didn't switch to \(scene)")
        // Let the color change settle before the shot.
        Thread.sleep(forTimeInterval: 0.6)
    }

    /// Taps update the UI on the next frames, so a check right after `tap()` can run before
    /// it changes on a slow simulator. Wait for it instead.
    private func waitFor(_ element: XCUIElement, _ format: String, _ message: String) {
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: format), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [changed], timeout: Self.wait), .completed, message)
    }

    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<16 where !element.isHittable {
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
