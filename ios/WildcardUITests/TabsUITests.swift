import XCTest

/// The tab bar over the signed-in app: every tab opens from it, and it steps aside while a
/// check-in is being written.
@MainActor
final class TabsUITests: XCTestCase {
    func testTabsSwitchAndStepAsideWhileComposing() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push", "-uitest-photos", "1",
        ]
        app.launch()
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }

        let today = app.buttons["tab.today"]
        XCTAssertTrue(today.waitForExistence(timeout: 30), "no tab bar")
        XCTAssertTrue(today.isSelected, "the app didn't open on 今天")
        XCTAssertEqual(
            ["tab.today", "tab.feed", "tab.schedule", "tab.me"].map { app.buttons[$0].label },
            ["今天", "动态", "出赛表", "我"])
        // 打卡 sits above the bar, not under it.
        let checkIn = app.buttons["today.checkin"]
        XCTAssertTrue(checkIn.isHittable, "打卡 is covered")
        XCTAssertLessThan(checkIn.frame.maxY, today.frame.minY, "打卡 overlaps the tab bar")
        Thread.sleep(forTimeInterval: 1)
        keepScreenshot(named: "30-tabs-today")

        let upcoming = app.staticTexts["tab.upcoming"]
        app.buttons["tab.feed"].tap()
        waitFor(app.buttons["tab.feed"], "isSelected == true", "tab.feed didn't open")
        XCTAssertEqual(upcoming.label, "动态", "tab.feed shows another tab's screen")
        XCTAssertFalse(checkIn.exists, "今天 still shows under tab.feed")
        app.buttons["tab.schedule"].tap()
        waitFor(app.buttons["tab.schedule"], "isSelected == true", "出赛表 didn't open")
        XCTAssertTrue(app.buttons["schedule.save"].waitForExistence(timeout: 30), "出赛表 shows another tab's screen")
        XCTAssertFalse(checkIn.exists, "今天 still shows under 出赛表")
        app.buttons["tab.me"].tap()
        waitFor(app.buttons["tab.me"], "isSelected == true", "tab.me didn't open")
        let mePage = app.descendants(matching: .any).matching(identifier: "me.page").firstMatch
        XCTAssertTrue(mePage.waitForExistence(timeout: 30), "我 didn't show its page")
        XCTAssertFalse(upcoming.exists, "我 shows another tab's screen")
        XCTAssertFalse(checkIn.exists, "今天 still shows under tab.me")
        app.buttons["tab.today"].tap()
        waitFor(today, "isSelected == true", "今天 didn't open again")
        XCTAssertFalse(mePage.exists, "the last tab's screen stayed over 今天")

        // The 打卡 burst takes the screen: the bar steps aside until it closes.
        checkIn.tap()
        let meal = app.buttons["today.capsule.healthyMeal"]
        XCTAssertTrue(meal.waitForExistence(timeout: 30))
        waitFor(today, "exists == false", "the tab bar stayed over the open burst")
        meal.tap()
        XCTAssertTrue(app.buttons["compose.post"].waitForExistence(timeout: 30), "the compose page never opened")
        waitFor(today, "exists == false", "the tab bar stayed over the compose page")
    }

    /// `-tab` opens straight on another tab, as screenshots of later tabs need.
    func testLaunchOnAnotherTab() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push", "-tab", "schedule",
        ]
        app.launch()
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }

        let schedule = app.buttons["tab.schedule"]
        XCTAssertTrue(schedule.waitForExistence(timeout: 30), "no tab bar")
        XCTAssertTrue(schedule.isSelected, "-tab schedule didn't open on 出赛表")
        XCTAssertTrue(app.buttons["schedule.save"].waitForExistence(timeout: 30), "-tab schedule didn't show 出赛表")
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
