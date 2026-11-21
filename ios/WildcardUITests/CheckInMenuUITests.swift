import XCTest

/// 打卡's ＋ at the tab bar's end and the check-in kinds it opens into (Tracy, 2026-11-21).
@MainActor
final class CheckInMenuUITests: XCTestCase {
    private static let wait: TimeInterval = 15
    private static let kinds = ["trained", "healthyMeal", "cheatMeal", "disclaimer"]

    /// The kinds stand in one stack above the ＋, on screen, never touching each other or the
    /// bar, the narrowest on top and the widest next to the ＋: in Simplified Chinese at the
    /// default text size, and in the two languages with the longest words at a large one. Each
    /// launch costs a CI simulator about ten seconds, so the cases that can't overlap when these
    /// don't are left out.
    func testKindsStackByWidthAboveThePlus() {
        let cases = [
            ("zh-Hans", "UICTContentSizeCategoryL"), ("zh-Hant", "UICTContentSizeCategoryAccessibilityXL"),
            ("en", "UICTContentSizeCategoryAccessibilityXL"),
        ]
        for (language, size) in cases {
            let app = launch(language: language, size: size)
            let plus = app.buttons["today.checkin"]
            XCTAssertTrue(plus.waitForExistence(timeout: Self.wait), "no ＋")
            plus.tap()
            _ = app.buttons["today.capsule.disclaimer"].waitForExistence(timeout: Self.wait)
            settle()
            if language == "zh-Hans" { keepScreenshot(named: "14b-checkin-menu") }
            let frames = Self.kinds.map { kind -> CGRect in
                let capsule = app.buttons["today.capsule.\(kind)"]
                XCTAssertTrue(capsule.waitForExistence(timeout: Self.wait), "no \(kind) capsule")
                return capsule.frame
            }
            let screen = app.windows.firstMatch.frame
            let bar = app.buttons["tab.today"].frame
            let tag = "\(language) \(size)"
            for (first, one) in frames.enumerated() {
                XCTAssertTrue(screen.contains(one), "\(tag): capsule \(first) leaves the screen")
                XCTAssertLessThan(one.maxY, plus.frame.minY, "\(tag): capsule \(first) runs into the ＋")
                XCTAssertLessThan(one.maxY, bar.minY, "\(tag): capsule \(first) runs into the bar")
                for (second, other) in frames.enumerated() where second > first {
                    XCTAssertFalse(one.intersects(other), "\(tag): capsules \(first) and \(second) overlap")
                }
            }
            // Top to bottom, each at least as wide as the one above it, right edges in line.
            let stack = frames.sorted { $0.minY < $1.minY }
            for (upper, lower) in zip(stack, stack.dropFirst()) {
                XCTAssertLessThanOrEqual(upper.width, lower.width + 1, "\(tag): a wider capsule sits higher")
                XCTAssertEqual(upper.maxX, lower.maxX, accuracy: 1, "\(tag): the stack's right edge isn't straight")
            }
            app.terminate()
        }
    }

    /// The ＋ is on every tab: from 动态 the kinds open over it with the bar still up, the ＋ (now a
    /// cross) puts them away, and a pick goes to 小队 and its compose page, which the bar leaves.
    func testCheckInFromAnotherTab() {
        let app = launch(language: "zh-Hans", size: "UICTContentSizeCategoryL")
        let plus = app.buttons["today.checkin"]
        XCTAssertTrue(plus.waitForExistence(timeout: Self.wait), "no ＋")
        app.buttons["tab.feed"].tap()
        XCTAssertTrue(app.staticTexts["feed.title"].waitForExistence(timeout: Self.wait), "动态 didn't open")
        XCTAssertTrue(plus.isHittable, "no ＋ on 动态")

        plus.tap()
        let meal = app.buttons["today.capsule.healthyMeal"]
        XCTAssertTrue(meal.waitForExistence(timeout: Self.wait), "the kinds didn't open on 动态")
        XCTAssertTrue(app.buttons["tab.feed"].isSelected, "the ＋ left 动态")
        XCTAssertTrue(app.buttons["tab.feed"].isHittable, "the bar stepped aside for the kinds")
        XCTAssertEqual(plus.label, "收起", "the cross isn't 收起")
        settle()
        keepScreenshot(named: "14c-checkin-menu-on-feed")
        plus.tap()
        waitFor(meal, "exists == false", "the cross didn't put the kinds away")

        // A tab tapped in the bar puts them away too, the open one included.
        plus.tap()
        XCTAssertTrue(meal.waitForExistence(timeout: Self.wait), "the kinds didn't open again")
        app.buttons["tab.feed"].tap()
        waitFor(meal, "exists == false", "tapping the open tab didn't put the kinds away")

        plus.tap()
        XCTAssertTrue(meal.waitForExistence(timeout: Self.wait), "the kinds didn't open a third time")
        meal.tap()
        XCTAssertTrue(app.buttons["compose.post"].waitForExistence(timeout: Self.wait), "the compose page never opened")
        waitFor(app.buttons["tab.feed"], "exists == false", "the tab bar stayed over the compose page")
    }

    private func launch(language: String, size: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-uitest-photos", "0", "-AppleLanguages", "(\(language))", "-AppleLocale", language,
            "-uitest-no-push", "-uitest-noon", "-today.cardPage", "0",
            "-UIPreferredContentSizeCategoryName", size, "-uitest-card-folded",
        ]
        app.launch()
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }
        return app
    }

    private func waitFor(_ element: XCUIElement, _ predicate: String, _ message: String) {
        let met = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [met], timeout: Self.wait), .completed, message)
    }

    private func settle() { Thread.sleep(forTimeInterval: 1) }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
