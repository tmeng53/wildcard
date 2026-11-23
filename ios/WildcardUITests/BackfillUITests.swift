import XCTest

/// 补打卡: a post can count for today or a day of the week before it, picked from its page's 日期
/// pill, which opens the week's strip (Tracy, 2026-11-21); 动态 shows it on the day it went up,
/// with 「补昨天的」 after its time. The 健康餐 compose page has its own placeholder, no sport row,
/// and the one photo as cover.
@MainActor
final class BackfillUITests: XCTestCase {
    private static let wait: TimeInterval = 30

    /// The pill says 今天 and opens the strip on today; picking yesterday and 完成 puts 昨天 on
    /// it, and posting a 健康餐 puts it in 动态 today, marked 补昨天的.
    func testPostForYesterday() {
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

        pickYesterday(in: app)
        rateTheMeal(in: app)

        caption.tap()
        caption.typeText("补一顿沙拉")
        app.buttons["compose.post"].tap()
        XCTAssertTrue(caption.waitForNonExistence(timeout: Self.wait), "the post didn't land")
        // 已发出's 查看 opens the post in 动态.
        let outgoing = app.buttons["today.outgoing"]
        waitFor(outgoing, "label CONTAINS '已发出'", "the post didn't go out")
        outgoing.tap()
        waitFor(app.buttons["tab.feed"], "isSelected == true", "查看 didn't open 动态")
        let label = app.staticTexts.matching(identifier: "post.backfill").firstMatch
        XCTAssertTrue(label.waitForExistence(timeout: Self.wait), "the post isn't marked as a 补打卡")
        XCTAssertEqual(label.label, "补昨天的")
        assertRatedFiveAndFour(in: app)
        settle()
        keepScreenshot(named: "63-feed-backfill")
    }

    /// The 日期 pill opens a week of days, today picked; yesterday and 完成 put 昨天 on the pill.
    private func pickYesterday(in app: XCUIApplication) {
        let dayPill = app.buttons["compose.day"]
        XCTAssertTrue(dayPill.waitForExistence(timeout: Self.wait), "no 日期 pill")
        XCTAssertEqual(dayPill.value as? String, "今天")
        XCTAssertFalse(app.buttons["dayStrip.7"].exists, "the strip shows before the pill is tapped")
        dayPill.tap()
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
        app.buttons["day.done"].tap()
        XCTAssertTrue(today.waitForNonExistence(timeout: Self.wait), "完成 didn't close the strip")
        XCTAssertEqual(dayPill.value as? String, "昨天", "the pill doesn't say the day picked")
    }

    /// A meal's page asks 这顿怎么样 under 日期: five stars for 健康 and five for 好吃, picked by a
    /// tap on the fifth and the fourth.
    private func rateTheMeal(in app: XCUIApplication) {
        let healthy = app.descendants(matching: .any).matching(identifier: "compose.healthy").firstMatch
        let tasty = app.descendants(matching: .any).matching(identifier: "compose.tasty").firstMatch
        XCTAssertTrue(healthy.waitForExistence(timeout: Self.wait), "a meal has no 这顿怎么样")
        XCTAssertTrue(tasty.exists, "a meal has no 好吃 stars")
        if !tasty.isHittable { app.swipeUp() }
        XCTAssertTrue(healthy.isHittable && tasty.isHittable, "这顿怎么样 is covered")
        healthy.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        tasty.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)).tap()
        settle()
        keepScreenshot(named: "62-compose-meal-rating")
    }

    /// Rated 5 and 4 on its page, the meal carries them on its 成绩条 in 动态.
    private func assertRatedFiveAndFour(in app: XCUIApplication) {
        let rated = app.descendants(matching: .any).matching(identifier: "feed.post")
            .containing(.any, identifier: "post.backfill").firstMatch
        let healthy = rated.descendants(matching: .any).matching(identifier: "strip.healthy").firstMatch
        XCTAssertTrue(healthy.waitForExistence(timeout: Self.wait), "the rated meal has no 成绩条")
        XCTAssertTrue(healthy.label.hasPrefix("5"), "健康 reads \(healthy.label)")
        let tasty = rated.descendants(matching: .any).matching(identifier: "strip.tasty").firstMatch
        XCTAssertTrue(tasty.label.hasPrefix("4"), "好吃 reads \(tasty.label)")
    }

    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-uitest-photos", "1", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push",
            "-uitest-noon", "-today.cardPage", "0",
            // 已发出 holds a minute, so a slow simulator still finds its 查看.
            "-uitest-bubble-hold",
        ]
        // Home opens on the folded capsule, as these tests were written for.
        app.launchArguments.append("-uitest-card-folded")
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
