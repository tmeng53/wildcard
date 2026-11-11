import XCTest

/// 补打卡: a post can count for today or a day of the week before it, picked on the 日期 strip of
/// its page; 动态 shows it on the day it went up, with 「补昨天的」 after its time. One launch walks
/// both pages, the 健康餐 compose page first (its own placeholder, no sport row, the one photo as
/// cover), since each launch costs a CI simulator about ten seconds.
@MainActor
final class BackfillUITests: XCTestCase {
    private static let wait: TimeInterval = 30

    /// The strip opens on today; picking yesterday and posting a 健康餐 puts it in 动态 today,
    /// marked 补昨天的. Then the 请假条 page has the same strip, its title following the day picked.
    func testPostForYesterdayThenADisclaimerForAPastDay() {
        let app = launch()
        app.buttons["today.checkin"].tap()
        let meal = app.buttons["today.capsule.healthyMeal"]
        XCTAssertTrue(meal.waitForExistence(timeout: Self.wait), "no 健康餐 capsule")
        meal.tap()
        let caption = app.descendants(matching: .any).matching(identifier: "compose.caption").firstMatch
        XCTAssertTrue(caption.waitForExistence(timeout: Self.wait), "the compose page never opened")
        XCTAssertEqual(caption.placeholderValue, "这顿很自律…")
        XCTAssertFalse(app.buttons["compose.sport.run"].exists, "a meal shows the sport row")
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "compose.cover").firstMatch.exists,
            "the one photo isn't the cover")
        settle()
        keepScreenshot(named: "22-compose-healthy-meal")

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
        XCTAssertTrue(caption.waitForNonExistence(timeout: Self.wait), "the post didn't land")
        app.buttons["tab.feed"].tap()
        waitFor(app.buttons["tab.feed"], "isSelected == true", "动态 didn't open")
        let label = app.staticTexts.matching(identifier: "post.backfill").firstMatch
        XCTAssertTrue(label.waitForExistence(timeout: Self.wait), "the post isn't marked as a 补打卡")
        XCTAssertEqual(label.label, "补昨天的")
        settle()
        keepScreenshot(named: "63-feed-backfill")

        disclaimerForAPastDay(in: app)
    }

    /// Back on 今天, the 请假条 page has the same strip, its title following the day picked.
    private func disclaimerForAPastDay(in app: XCUIApplication) {
        tabButton("tab.today", in: app).tap()
        let checkIn = app.buttons["today.checkin"]
        XCTAssertTrue(checkIn.waitForExistence(timeout: Self.wait), "no 打卡 button back on 今天")
        checkIn.tap()
        let disclaimer = app.buttons["today.capsule.disclaimer"]
        XCTAssertTrue(disclaimer.waitForExistence(timeout: Self.wait), "no 请假条 capsule")
        disclaimer.tap()
        // A week ago is never in the sample's week, so it has no 练了.
        let weekAgo = app.buttons["dayStrip.0"]
        XCTAssertTrue(weekAgo.waitForExistence(timeout: Self.wait), "no 日期 strip on the 请假条 page")
        XCTAssertTrue(app.staticTexts["今日请假条"].exists, "today's 请假条 isn't 今日请假条")
        // The page opens with the keyboard up for the excuse; the 日期 strip sits under the ticket,
        // so Return puts the keyboard away first.
        if app.keyboards.firstMatch.exists {
            app.typeText("\n")
            waitFor(app.keyboards.firstMatch, "exists == false", "Return left the keyboard up")
        }
        XCTAssertTrue(weekAgo.isHittable, "the 日期 strip is covered")
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
            "-uitest-photos", "1", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push",
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
