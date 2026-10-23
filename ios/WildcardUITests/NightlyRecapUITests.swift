import XCTest

/// 今日赛况 on 今天, on the sample squad at 21:30, with screenshots for review.
@MainActor
final class NightlyRecapUITests: XCTestCase {
    /// Slow CI simulators can take many seconds to show a screen; a real failure still fails.
    private static let wait: TimeInterval = 30

    /// 今日赛况 at 21:30: the tag on the squad card has its dot, opens the box score (three
    /// trained, one 请假条, one rest day; nobody else), folds back and keeps the tag, now seen.
    func testNightlyRecap() {
        let app = XCUIApplication()
        continueAfterFailure = false
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push", "-uitest-evening",
            "-today.cardPage", "0", "-uitest-recap-unseen",
        ]
        app.launch()
        let card = app.descendants(matching: .any).matching(identifier: "today.card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: Self.wait), "今天 never appeared")
        let tag = app.buttons["today.recap.tag"]
        XCTAssertTrue(tag.waitForExistence(timeout: Self.wait), "no 今日赛况 tag at 21:30")
        XCTAssertEqual(tag.label, "今日赛况，还没看")
        XCTAssertEqual(tag.value as? String, "4/8")
        settle()
        keepScreenshot(named: "18-today-recap-tag")

        tag.tap()
        let recap = app.descendants(matching: .any).matching(identifier: "today.recap").firstMatch
        XCTAssertTrue(recap.waitForExistence(timeout: Self.wait), "the box score didn't open")
        XCTAssertTrue(labeled("4/8", in: app).waitForExistence(timeout: Self.wait), "the score didn't roll up to 4/8")
        // Let the score roll before the shot.
        Thread.sleep(forTimeInterval: 1.2)
        keepScreenshot(named: "19-today-recap-open")
        // The box score stays on screen and clear of 打卡.
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(window.contains(recap.frame), "the box score runs off the screen: \(recap.frame)")
        XCTAssertLessThan(
            recap.frame.maxY, app.buttons["today.checkin"].frame.minY, "the box score runs under 打卡: \(recap.frame)")

        app.buttons["today.recap.close"].tap()
        XCTAssertTrue(recap.waitForNonExistence(timeout: Self.wait), "收起 didn't fold the box score")
        XCTAssertTrue(tag.waitForExistence(timeout: Self.wait), "the tag went away after 收起")
        XCTAssertEqual(tag.label, "今日赛况")
        settle()
        keepScreenshot(named: "20-today-recap-seen")
    }

    private func labeled(_ label: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// Lets springs and blurs settle before a screenshot.
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
