import XCTest

/// 补打卡: a post can count for today or a day of the week before it, picked on the 日期 strip of
/// its page; 动态 shows it on the day it went up, with 「补昨天的」 after its time.
@MainActor
final class BackfillUITests: XCTestCase {
    private static let wait: TimeInterval = 30

    /// The strip opens on today; picking yesterday and posting puts the post in 动态 today,
    /// marked 补昨天的.
    func testPostForYesterday() {
        let app = launch()
        app.buttons["today.checkin"].tap()
        let meal = app.buttons["today.capsule.healthyMeal"]
        XCTAssertTrue(meal.waitForExistence(timeout: Self.wait), "no 健康餐 capsule")
        meal.tap()
        let caption = app.descendants(matching: .any).matching(identifier: "compose.caption").firstMatch
        XCTAssertTrue(caption.waitForExistence(timeout: Self.wait), "the compose page never opened")

        // Eight days, the earliest first: today is the last, and picked.
        let today = app.buttons["dayStrip.7"]
        let yesterday = app.buttons["dayStrip.6"]
        XCTAssertTrue(today.waitForExistence(timeout: Self.wait), "no 日期 strip")
        XCTAssertTrue(app.buttons["dayStrip.0"].exists, "the strip doesn't reach a week back")
        XCTAssertFalse(app.buttons["dayStrip.8"].exists, "the strip reaches past a week back")
        XCTAssertTrue(today.isSelected, "the strip didn't open on today")
        XCTAssertTrue(today.label.hasPrefix("今天"), "today isn't called 今天: \(today.label)")
        for index in 0...7 {
            let day = app.buttons["dayStrip.\(index)"]
            XCTAssertTrue(app.windows.firstMatch.frame.contains(day.frame), "day \(index) is cut off: \(day.frame)")
        }

        yesterday.tap()
        waitFor(yesterday, "isSelected == true", "tapping yesterday didn't pick it")
        XCTAssertFalse(today.isSelected, "today stayed picked")
        settle()
        keepScreenshot(named: "62-compose-backfill-yesterday")

        caption.tap()
        caption.typeText("补一顿沙拉")
        app.buttons["compose.post"].tap()
        let bubble = app.descendants(matching: .any).matching(identifier: "today.bubble").firstMatch
        XCTAssertTrue(bubble.waitForExistence(timeout: Self.wait), "the post didn't land")
        bubble.tap()
        waitFor(app.buttons["tab.feed"], "isSelected == true", "tapping the bubble didn't open 动态")
        let label = app.staticTexts.matching(identifier: "post.backfill").firstMatch
        XCTAssertTrue(label.waitForExistence(timeout: Self.wait), "the post isn't marked as a 补打卡")
        XCTAssertEqual(label.label, "补昨天的")
        settle()
        keepScreenshot(named: "63-feed-backfill")
    }

    /// The 请假条 page has the same strip, its title following the day picked.
    func testDisclaimerForAPastDay() {
        let app = launch()
        app.buttons["today.checkin"].tap()
        let disclaimer = app.buttons["today.capsule.disclaimer"]
        XCTAssertTrue(disclaimer.waitForExistence(timeout: Self.wait), "no 请假条 capsule")
        disclaimer.tap()
        // A week ago is never in the sample's week, so it has no 练了.
        let weekAgo = app.buttons["dayStrip.0"]
        XCTAssertTrue(weekAgo.waitForExistence(timeout: Self.wait), "no 日期 strip on the 请假条 page")
        XCTAssertTrue(app.staticTexts["今日请假条"].exists, "today's 请假条 isn't 今日请假条")
        weekAgo.tap()
        waitFor(weekAgo, "isSelected == true", "tapping a week ago didn't pick it")
        XCTAssertTrue(app.staticTexts["请假条"].waitForExistence(timeout: Self.wait), "the title didn't follow the day")
        settle()
        keepScreenshot(named: "64-disclaimer-backfill")
    }

    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-uitest-photos", "0", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push",
            "-uitest-noon", "-today.cardPage", "0",
        ]
        app.launch()
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }
        let checkIn = app.buttons["today.checkin"]
        XCTAssertTrue(checkIn.waitForExistence(timeout: Self.wait), "no 打卡 button")
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
