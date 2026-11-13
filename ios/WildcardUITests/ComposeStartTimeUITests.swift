import XCTest

/// The start of a 训练 on the compose page: its clock pill and the flip clock it opens.
@MainActor
final class ComposeStartTimeUITests: XCTestCase {
    private static let wait: TimeInterval = 30

    /// The pill starts on the phone's time and opens the flip clock on it; turning the hour up one
    /// and 完成 puts that time on the pill, and a tap on it opens the clock again, never clears it.
    func testPickAStartOnTheFlipClock() {
        let app = launch()
        let checkIn = app.buttons["today.checkin"]
        XCTAssertTrue(checkIn.waitForExistence(timeout: Self.wait), "no 打卡 button")
        checkIn.tap()
        let trained = app.buttons["today.capsule.trained"]
        XCTAssertTrue(trained.waitForExistence(timeout: Self.wait), "no 训练 capsule")
        trained.tap()
        let pill = app.buttons["compose.start"]
        XCTAssertTrue(pill.waitForExistence(timeout: Self.wait), "no start pill on the compose page")
        let shown = pill.value as? String ?? ""
        let isTime = shown.range(of: #"^\d{2}:\d{2}$"#, options: .regularExpression) != nil
        XCTAssertTrue(isTime, "the start is \(shown), not the time")
        XCTAssertTrue(app.buttons["compose.minutes.60"].exists, "the lengths aren't beside the start")
        settle()
        keepScreenshot(named: "15-compose-start-row")

        pill.tap()
        let hour = app.descendants(matching: .any).matching(identifier: "start.hour").firstMatch
        let minute = app.descendants(matching: .any).matching(identifier: "start.minute").firstMatch
        XCTAssertTrue(hour.waitForExistence(timeout: Self.wait), "the flip clock didn't open")
        let opened = Int(hour.value as? String ?? "") ?? -1
        XCTAssertEqual(opened, Int(shown.prefix(2)), "the clock didn't open on the pill's time")
        // The card's up chevron, at the top of the hour column. XCUIElement.increment() is macOS
        // only; on iOS the column is one adjustable element whose chevron a tap still reaches.
        hour.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        settle()
        let turned = (opened + 1) % 24
        XCTAssertEqual(Int(hour.value as? String ?? ""), turned, "the hour didn't turn up one")
        keepScreenshot(named: "15-compose-start-clock")
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(window.contains(hour.frame), "the hour card is cut off: \(hour.frame)")
        XCTAssertTrue(window.contains(minute.frame), "the minute card is cut off: \(minute.frame)")

        let picked = String(format: "%02d:%@", turned, minute.value as? String ?? "")
        app.buttons["start.done"].tap()
        XCTAssertTrue(hour.waitForNonExistence(timeout: Self.wait), "完成 didn't close the flip clock")
        XCTAssertEqual(pill.value as? String, picked, "the pill doesn't show the picked start")

        // Every 训练 has a start: a tap opens the clock on it again, and 取消 keeps it.
        pill.tap()
        XCTAssertTrue(hour.waitForExistence(timeout: Self.wait), "tapping the start didn't open the clock")
        XCTAssertEqual(Int(hour.value as? String ?? ""), turned, "the clock didn't open on the picked start")
        app.buttons["start.cancel"].tap()
        XCTAssertTrue(hour.waitForNonExistence(timeout: Self.wait), "取消 didn't close the flip clock")
        XCTAssertEqual(pill.value as? String, picked, "取消 changed the start")
    }

    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push", "-uitest-noon",
            "-today.cardPage", "0",
        ]
        // Home opens on the folded capsule, as these tests were written for.
        app.launchArguments.append("-uitest-card-folded")
        app.launch()
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }
        return app
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
