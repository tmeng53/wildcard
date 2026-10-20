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

        for tab in ["tab.feed", "tab.schedule", "tab.me"] {
            app.buttons[tab].tap()
            waitFor(app.buttons[tab], "isSelected == true", "\(tab) didn't open")
        }
        app.buttons["tab.today"].tap()
        waitFor(today, "isSelected == true", "今天 didn't open again")

        checkIn.tap()
        let meal = app.buttons["today.capsule.healthyMeal"]
        XCTAssertTrue(meal.waitForExistence(timeout: 30))
        meal.tap()
        XCTAssertTrue(app.buttons["compose.post"].waitForExistence(timeout: 30), "the compose page never opened")
        waitFor(today, "exists == false", "the tab bar stayed over the compose page")
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
